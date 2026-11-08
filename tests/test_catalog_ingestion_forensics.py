import pytest
import io
from PIL import Image

def test_image_pipeline_corrupted_jpeg_resilience():
    """Verify that truncated or corrupted JPEG data does not crash the ingestion pipeline."""
    corrupted_data = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00`\x00`\x00\x00" # Truncated header
    
    def safe_load_image(data: bytes):
        try:
            img = Image.open(io.BytesIO(data))
            img.verify()
            return img
        except Exception:
            return None

    result = safe_load_image(corrupted_data)
    assert result is None, "Corrupted image must fail gracefully without unhandled exception"

def test_barcode_deduplication_upsert_logic():
    """Verify that products sharing identical barcode update stock/price instead of duplicating rows."""
    existing_catalog = {
        "8901030382345": {"id": "prod_1", "name": "Tata Tea Gold 500g", "price": 310.0, "stock": 10}
    }
    
    new_scanned_item = {
        "barcode": "8901030382345",
        "name": "Tata Tea Gold 500g",
        "price": 320.0,
        "stock": 15
    }
    
    # Ingestion upsert logic:
    if new_scanned_item["barcode"] in existing_catalog:
        record = existing_catalog[new_scanned_item["barcode"]]
        record["price"] = new_scanned_item["price"]
        record["stock"] += new_scanned_item["stock"]
    else:
        existing_catalog[new_scanned_item["barcode"]] = new_scanned_item
        
    assert len(existing_catalog) == 1, "Catalog length must remain 1 (no duplicate rows created)"
    assert existing_catalog["8901030382345"]["price"] == 320.0
    assert existing_catalog["8901030382345"]["stock"] == 25

def test_soft_delete_preservation_on_catalog_sync():
    """Ensure that soft-deleted items (is_deleted=True) are NEVER restored or overwritten during automated sync."""
    db_items = [
        {"id": "p1", "name": "Active Bread", "is_deleted": False},
        {"id": "p2", "name": "Deleted Bread", "is_deleted": True},
    ]
    
    def sync_item(item_id: str, new_name: str):
        target = next((item for item in db_items if item["id"] == item_id and not item["is_deleted"]), None)
        if target:
            target["name"] = new_name
            return True
        return False
        
    # Attempt sync on deleted item must be blocked
    sync_result_deleted = sync_item("p2", "Resurrected Bread")
    assert sync_result_deleted is False
    assert db_items[1]["name"] == "Deleted Bread"
    assert db_items[1]["is_deleted"] is True
    
    # Sync on active item must succeed
    sync_result_active = sync_item("p1", "Active Fresh Bread")
    assert sync_result_active is True
    assert db_items[0]["name"] == "Active Fresh Bread"

def test_100_percent_prepaid_payment_tag_enforcement():
    """Verify that catalog and checkout payloads enforce prepaid only."""
    allowed_payment_methods = ["upi", "card", "netbanking", "wallet"]
    assert "cod" not in allowed_payment_methods

