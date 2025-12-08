#!/usr/bin/env python3

import requests
import json
import uuid
import os
from datetime import datetime, timedelta
import urllib3

# Disable SSL warnings when using ALB hostname directly (certificate is for domain, not ALB)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Configuration - Read from environment or fall back to localhost
API_BASE_URL = os.getenv('API_BASE_URL', 'http://localhost')

BASE_URLS = {
    'user': f"{API_BASE_URL}/api/user",
    'event': f"{API_BASE_URL}/api/event", 
    'booking': f"{API_BASE_URL}/api/booking"
}

# Session with SSL verification disabled for ALB hostname
session = requests.Session()
session.verify = False

def create_user(email, password, first_name, last_name):
    url = f"{BASE_URLS['user']}/auth/register"
    data = {
        "email": email,
        "password": password,
        "name": f"{first_name} {last_name}"
    }
    response = session.post(url, json=data)
    print(f"Registration response status: {response.status_code}")
    print(f"Registration response: {response.text}")
    return response.json() if response.status_code == 201 else None

def login_user(email, password):
    url = f"{BASE_URLS['user']}/auth/login"
    data = {"email": email, "password": password}
    response = session.post(url, json=data)
    return response.json() if response.status_code == 200 else None

def create_admin(email, password, name):
    url = f"{BASE_URLS['event']}/auth/admin/register"
    data = {
        "email": email,
        "password": password,
        "name": name
    }
    response = session.post(url, json=data)
    print(f"Admin registration response status: {response.status_code}")
    print(f"Admin registration response: {response.text}")
    return response.json() if response.status_code == 201 else None

def login_admin(email, password):
    url = f"{BASE_URLS['event']}/auth/admin/login"
    data = {"email": email, "password": password}
    response = session.post(url, json=data)
    print(f"Admin login response status: {response.status_code}")
    print(f"Admin login response: {response.text}")
    return response.json() if response.status_code == 200 else None

def create_venue(token, name="Test Venue", capacity=500):
    """Create a venue using admin token"""
    url = f"{BASE_URLS['event']}/admin/venues"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    data = {
        "name": name,
        "address": "123 Test St",
        "city": "Test City",
        "state": "TS",
        "country": "USA",
        "postal_code": "12345",
        "capacity": capacity
    }
    response = session.post(url, json=data, headers=headers)
    if response.status_code == 201:
        return response.json().get("venue_id")
    else:
        print(f"Venue creation failed: {response.status_code} - {response.text}")
        return None

def create_admin_event(token, name, venue_id=None, total_seats=100, base_price=29.99, days_offset=30):
    url = f"{BASE_URLS['event']}/admin/events"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    # If no venue_id provided, generate one (will fail, but kept for compatibility)
    if not venue_id:
        venue_id = str(uuid.uuid4())
    # Use timezone-aware datetime to avoid issues
    from datetime import timezone
    now = datetime.now(timezone.utc)
    start_date = (now + timedelta(days=days_offset)).strftime("%Y-%m-%dT%H:%M:%SZ")
    end_date = (now + timedelta(days=days_offset, hours=3)).strftime("%Y-%m-%dT%H:%M:%SZ")
    
    data = {
        "name": name,
        "description": f"Test event: {name}",
        "event_type": "conference",
        "venue_id": venue_id,
        "start_datetime": start_date,  # Changed from start_date
        "end_datetime": end_date,      # Changed from end_date
        "total_capacity": total_seats,  # Changed from total_seats
        "available_seats": total_seats,
        "base_price": base_price,
        "max_tickets_per_booking": 8,
        "status": "published"
    }
    print(f"Sending event data: start_datetime={start_date}, end_datetime={end_date}")
    response = session.post(url, json=data, headers=headers)
    print(f"Event creation response status: {response.status_code}")
    print(f"Event creation response: {response.text}")
    
    # If event was created successfully, publish it
    event_data = response.json() if response.status_code == 201 else None
    if event_data and event_data.get('event_id'):
        # Publish the event
        publish_url = f"{BASE_URLS['event']}/admin/events/{event_data['event_id']}"
        publish_data = {
            "status": "published",
            "version": event_data.get('version', 1)  # Include version for optimistic locking
        }
        publish_response = session.put(publish_url, json=publish_data, headers=headers)
        if publish_response.status_code == 200:
            print(f"✓ Event published successfully")
            return publish_response.json()
        else:
            print(f"✗ Event publish failed: {publish_response.status_code} - {publish_response.text}")
    
    return event_data

def get_events(token):
    url = f"{BASE_URLS['event']}/events"
    headers = {"Authorization": f"Bearer {token}"}
    response = session.get(url, headers=headers)
    return response.json()

def check_availability(event_id, quantity=2):
    url = f"{BASE_URLS['booking']}/bookings/check-availability"
    params = {"event_id": event_id, "quantity": quantity}
    response = session.get(url, params=params)
    return response.json()

def reserve_seats(token, event_id, quantity=2):
    url = f"{BASE_URLS['booking']}/bookings/reserve"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    data = {
        "event_id": event_id,
        "quantity": quantity,
        "idempotency_key": str(uuid.uuid4())
    }
    response = session.post(url, json=data, headers=headers)
    return response.json(), response.status_code

def confirm_booking(token, reservation_id):
    url = f"{BASE_URLS['booking']}/bookings/confirm"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    data = {
        "reservation_id": reservation_id,
        "payment_token": f"mock_token_{uuid.uuid4()}",
        "payment_method": "credit_card"
    }
    response = session.post(url, json=data, headers=headers)
    return response.json(), response.status_code

def main():
    print("=== Booking Service Flow Test ===")
    
    # Use timestamp-based unique emails to avoid conflicts
    import time
    timestamp = int(time.time())
    user_email = f"testuser{timestamp}@example.com"
    admin_email = f"testadmin{timestamp}@example.com"
    
    print(f"\n1. Creating regular user ({user_email})...")
    claude_user = create_user(user_email, "password123", "Test", "User")
    if claude_user:
        print(f"✓ User created successfully")
    else:
        print(f"✗ User creation failed - trying to login with existing credentials...")
    
    print(f"\n2. Creating admin user ({admin_email})...")
    admin_user = create_admin(admin_email, "admin123", "Test Admin")
    if admin_user:
        print(f"✓ Admin created successfully")
    else:
        print(f"✗ Admin creation failed - trying to login with existing credentials...")
    
    print("\n3. Logging in users...")
    claude_login = login_user(user_email, "password123")
    admin_login = login_admin(admin_email, "admin123")
    
    if claude_login and 'access_token' in claude_login:
        print(f"✓ User login successful")
    else:
        print(f"✗ User login failed: {claude_login}")
    
    if admin_login and 'access_token' in admin_login:
        print(f"✓ Admin login successful")
    else:
        print(f"✗ Admin login failed: {admin_login}")
        print("\n⚠️  WARNING: Admin functionality unavailable")
        print("   This is expected if admin schema migrations haven't been run.")
        print("   Continuing with user-level testing only...\n")
    
    if not claude_login or 'access_token' not in (claude_login or {}):
        print("\n❌ CRITICAL: User login failed - cannot continue testing")
        print("   Please check:")
        print("   - User service is running")
        print("   - Database migrations completed")
        print("   - API_BASE_URL is correct")
        return
    
    claude_token = claude_login.get('access_token')
    print(f"User Token: {claude_token[:30]}...")
    
    # Skip admin-dependent tests if admin login failed
    if not admin_login or 'access_token' not in (admin_login or {}):
        print("\n4. Skipping event creation (requires admin)")
        print("5. Getting existing events instead...")
        available_events = get_events(claude_token)
        print(f"Available events: {available_events}")
        
        if not available_events.get('events'):
            print("\n⚠️  No events found in database")
            print("   Admin access needed to create test events")
            print("   Test incomplete - please fix admin registration")
            return
    else:
        admin_token = admin_login.get('access_token')
        print(f"Admin Token: {admin_token[:30]}...")
        
        print("\n4. Creating test venue...")
        venue_id = create_venue(admin_token, "Main Concert Hall", 500)
        if venue_id:
            print(f"✓ Venue created: {venue_id}")
        else:
            print("✗ Venue creation failed - cannot create events")
            return
        
        print("\n5. Creating test events...")
        events = [
            create_admin_event(admin_token, "Tech Conference 2024", venue_id, 200, 99.99, days_offset=30),
            create_admin_event(admin_token, "Music Concert", venue_id, 150, 49.99, days_offset=35),
            create_admin_event(admin_token, "Comedy Show", venue_id, 80, 25.99, days_offset=40)
        ]
        
        for i, event in enumerate(events, 1):
            if event:
                print(f"✓ Event {i} created: {event.get('event_id', 'Unknown')}")
            else:
                print(f"✗ Event {i} creation failed")
        
        print("\n6. Getting available events...")
        available_events = get_events(claude_token)
        print(f"Found {len(available_events.get('events', []))} events")
    
    if not available_events.get('events'):
        print("❌ No events found - cannot test booking flow")
        return
    
    event_id = available_events['events'][0]['event_id']
    print(f"\n6. Testing booking flow for event: {event_id}")
    
    print("\n7. Checking availability...")
    availability = check_availability(event_id, 2)
    print(f"Availability: {availability}")
    
    print("\n8. Reserving seats (Phase 1)...")
    reservation, status = reserve_seats(claude_token, event_id, 2)
    print(f"Reservation (Status {status}): {reservation}")
    
    if status != 200 or 'reservation_id' not in reservation:
        print("Failed to reserve seats!")
        return
    
    reservation_id = reservation['reservation_id']
    
    print("\n9. Confirming booking (Phase 2)...")
    confirmation, status = confirm_booking(claude_token, reservation_id)
    print(f"Confirmation (Status {status}): {confirmation}")
    
    if status == 200:
        print("\n✅ SUCCESS: Complete booking flow worked!")
        print(f"Booking ID: {confirmation.get('booking_id')}")
        print(f"Ticket URL: {confirmation.get('ticket_url')}")
    else:
        print(f"\n❌ FAILED: Booking confirmation failed with status {status}")

if __name__ == "__main__":
    main()