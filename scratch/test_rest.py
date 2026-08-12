import os
import requests
import json
import random

# Read env
env = {}
with open('.env', 'r') as f:
    for line in f:
        if '=' in line:
            k, v = line.strip().split('=', 1)
            env[k] = v

url = env.get('SUPABASE_URL')
key = env.get('SUPABASE_ANON_KEY')

print("Testing signUp...")
rnd = random.randint(1000, 9999)
email = f"987654{rnd}@auth.enything.app"
password = "TestPassword123!"

res = requests.post(
    f"{url}/auth/v1/signup",
    headers={
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json"
    },
    json={
        "email": email,
        "password": password
    }
)
print("SignUp Status:", res.status_code)
print("SignUp Body:", json.dumps(res.json(), indent=2))
