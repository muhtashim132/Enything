#!/usr/bin/env python3
"""
Supabase uploader module — Handles database insertion and duplicate protection.

Rules & Edge Cases Enforced:
1. Soft Deletes: ALWAYS includes `is_deleted = false` when checking duplicates or querying products
2. Exact Schema Alignment: Perfectly mirrors Flutter's `add_product_page.dart` schema
3. Safe Encoding: Sanitizes special characters (+, %, &, /) in product names for PostgREST
4. Testing Discipline: Provides test purge function to guarantee ZERO leftover test records
5. Resilient Auth: Automatically supports service_role key or anon key

Zero cost. Direct REST API calls without extra SDKs.
"""

import json
import os
import re
import time
import urllib.parse
from pathlib import Path
import requests


def get_supabase_config() -> dict:
    """Load Supabase configuration from environment variables or .env file."""
    env_path = Path(__file__).parent.parent.parent / ".env"
    if env_path.exists():
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, _, value = line.partition("=")
                    os.environ.setdefault(key.strip(), value.strip())

    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get("SUPABASE_SERVICE_ROLE") or ""
    anon_key = os.environ.get("SUPABASE_ANON_KEY", "")

    key = service_key if service_key else anon_key

    return {
        "url": url,
        "key": key,
        "is_service_role": bool(service_key),
    }


def init_supabase(config: dict) -> bool:
    """Verify Supabase connection."""
    if not config.get("url") or not config.get("key"):
        return False
    try:
        resp = requests.get(
            f"{config['url']}/rest/v1/",
            headers={
                "apikey": config["key"],
                "Authorization": f"Bearer {config['key']}",
            },
            timeout=10,
        )
        return resp.status_code == 200
    except Exception as e:
        print(f"      ⚠️  Supabase connection check failed: {e}")
        return False


def check_duplicate_product(config: dict, shop_id: str, product_name: str) -> bool:
    """
    Check if a product already exists for this shop.
    MANDATORY RULE: Always filters by `is_deleted = false` (soft delete rule).
    Compares exact normalized name so different dosage forms/strengths (e.g. Augmentin 625 Duo Tablets
    vs Augmentin Duo Dry Suspension) are NEVER falsely skipped.
    """
    try:
        clean_name = product_name.strip()
        encoded_name = urllib.parse.quote_plus(clean_name)

        headers = {
            "apikey": config["key"],
            "Authorization": f"Bearer {config['key']}",
            "Content-Type": "application/json",
            "Prefer": "count=exact",
        }

        # Exact match check
        url = (
            f"{config['url']}/rest/v1/products"
            f"?shop_id=eq.{shop_id}"
            f"&is_deleted=eq.false"
            f"&name=ilike.{encoded_name}"
            f"&select=id,name"
        )

        resp = requests.get(url, headers=headers, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            # Verify exact normalized match
            for row in data:
                if row.get("name", "").strip().lower() == clean_name.lower():
                    return True

        return False
    except Exception as e:
        print(f"      ⚠️  Duplicate check warning: {e}")
        return False


def insert_product(config: dict, payload: dict) -> dict:
    """
    Insert a verified product into the `products` table.
    Mirrors Flutter app schema in `add_product_page.dart`.
    """
    headers = {
        "apikey": config["key"],
        "Authorization": f"Bearer {config['key']}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }

    url = f"{config['url']}/rest/v1/products"

    # Validation
    if not payload.get("shop_id"):
        print("      ❌ Missing shop_id")
        return None
    if not payload.get("name"):
        print("      ❌ Missing product name")
        return None
    if not payload.get("price") or payload["price"] <= 0:
        print("      ❌ Invalid price (<= 0)")
        return None

    # Ensure is_deleted is strictly false
    payload["is_deleted"] = False

    max_retries = 3
    for attempt in range(max_retries):
        try:
            resp = requests.post(
                url,
                json=payload,
                headers=headers,
                timeout=15,
            )

            if resp.status_code in (200, 201):
                data = resp.json()
                return data[0] if isinstance(data, list) and data else data

            elif resp.status_code == 409:
                print(f"      ⚠️  Conflict (duplicate constraint): {resp.text[:100]}")
                return None

            elif resp.status_code == 429:
                wait_sec = (attempt + 1) * 3
                print(f"      ⚠️  Rate limited, waiting {wait_sec}s...")
                time.sleep(wait_sec)

            elif resp.status_code in (401, 403):
                # Fallback to bulk_upload_shop_products SECURITY DEFINER RPC
                rpc_res = bulk_upload_products(config, payload["shop_id"], [payload])
                if rpc_res and (rpc_res.get("inserted", 0) > 0 or rpc_res.get("updated", 0) > 0):
                    status = "inserted" if rpc_res.get("inserted", 0) > 0 else "updated"
                    return {"name": payload["name"], "status": status}
                elif rpc_res and rpc_res.get("skipped", 0) > 0:
                    print(f"      ℹ️  Already exists in database: {payload['name']}")
                    return {"name": payload["name"], "status": "skipped"}
                else:
                    print(f"      ❌ Auth error ({resp.status_code}) and RPC failed: {resp.text[:200]}")
                    return None

            else:
                print(f"      ❌ Insert error ({resp.status_code}): {resp.text[:200]}")
                if attempt < max_retries - 1:
                    time.sleep(2)

        except requests.exceptions.Timeout:
            print(f"      ⚠️  Insert timeout on attempt {attempt + 1}")
            if attempt < max_retries - 1:
                time.sleep(2)
        except Exception as e:
            print(f"      ❌ Insert exception: {e}")
            if attempt < max_retries - 1:
                time.sleep(2)

    return None


def bulk_upload_products(config: dict, shop_id: str, products: list) -> dict:
    """
    Bulk upload a list of products using public.bulk_upload_shop_products RPC.
    Executes with SECURITY DEFINER privileges to prevent RLS blocks while
    strictly respecting soft deletes (is_deleted = false) and duplicate prevention.
    """
    if not shop_id or not products:
        return {"inserted": 0, "skipped": 0}

    # Ensure each product has is_deleted = False
    clean_products = []
    for p in products:
        prod_copy = dict(p)
        prod_copy["is_deleted"] = False
        clean_products.append(prod_copy)

    headers = {
        "apikey": config["key"],
        "Authorization": f"Bearer {config['key']}",
        "Content-Type": "application/json",
    }
    url = f"{config['url']}/rest/v1/rpc/bulk_upload_shop_products"

    try:
        resp = requests.post(
            url,
            headers=headers,
            json={"p_shop_id": shop_id, "p_products": clean_products},
            timeout=30,
        )
        if resp.status_code == 200:
            return resp.json()
        else:
            print(f"      ❌ bulk_upload_shop_products failed ({resp.status_code}): {resp.text[:200]}")
            return {"inserted": 0, "skipped": 0}
    except Exception as e:
        print(f"      ❌ bulk_upload_shop_products exception: {e}")
        return {"inserted": 0, "skipped": 0}


def purge_test_products(config: dict, shop_id: str, test_names: list) -> int:
    """
    Testing Discipline & Zero Test Leftovers rule:
    Purges any mock or test products created during automated verification
    using the privileged public.bulk_delete_shop_products RPC.
    """
    if not shop_id or not test_names:
        return 0

    headers = {
        "apikey": config["key"],
        "Authorization": f"Bearer {config['key']}",
        "Content-Type": "application/json",
    }

    try:
        url = f"{config['url']}/rest/v1/rpc/bulk_delete_shop_products"
        resp = requests.post(
            url,
            headers=headers,
            json={"p_shop_id": shop_id, "p_names": test_names},
            timeout=10,
        )
        if resp.status_code == 200:
            return resp.json().get("deleted", 0)
    except Exception as e:
        print(f"      ⚠️  bulk_delete_shop_products exception: {e}")

    # Fallback to direct DELETE
    deleted_count = 0
    for name in test_names:
        try:
            encoded_name = urllib.parse.quote_plus(name)
            url = f"{config['url']}/rest/v1/products?shop_id=eq.{shop_id}&name=eq.{encoded_name}"
            resp = requests.delete(url, headers=headers, timeout=10)
            if resp.status_code in (200, 204):
                deleted_count += 1
        except Exception:
            pass

    return deleted_count



def get_shop_info(config: dict, shop_id: str) -> dict:
    """Fetch shop information to verify existence and check primary category."""
    try:
        headers = {
            "apikey": config["key"],
            "Authorization": f"Bearer {config['key']}",
            "Content-Type": "application/json",
        }
        url = f"{config['url']}/rest/v1/shops?id=eq.{shop_id}&select=id,name,category,categories,is_active"
        resp = requests.get(url, headers=headers, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            if data:
                return data[0]
        return {}
    except Exception as e:
        print(f"      ⚠️  Shop info fetch error: {e}")
        return {}


def get_shop_by_name(config: dict, shop_name: str) -> dict:
    """Fetch shop information by shop name."""
    try:
        headers = {
            "apikey": config["key"],
            "Authorization": f"Bearer {config['key']}",
            "Content-Type": "application/json",
        }
        encoded = urllib.parse.quote_plus(f"*{shop_name}*")
        url = f"{config['url']}/rest/v1/shops?name=ilike.{encoded}&select=id,name,category,categories,is_active&limit=1"
        resp = requests.get(url, headers=headers, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            if data:
                return data[0]
        return {}
    except Exception as e:
        print(f"      ⚠️  Shop info fetch error: {e}")
        return {}

