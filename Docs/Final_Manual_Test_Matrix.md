# UrbanShield Final Manual Test Matrix

Date: 2026-05-20

## Test Accounts

Use separate accounts so role and RLS behavior can be checked correctly.

- Admin A
- Coordinator A
- Citizen A
- Citizen B
- Citizen C, optional for extra nearby/request list testing

Initial setup:

- Admin A should already be admin in Supabase.
- Coordinator A can start as citizen, then Admin A promotes them to coordinator in the app.
- Citizen B will become volunteer by accepting Citizen A's request.

Required SQL before testing:

- `UrbanShield/Resources/Supabase/phase4_2_request_update_evidence.sql`
- `UrbanShield/Resources/Supabase/phase5_2_in_app_notifications.sql`
- `UrbanShield/Resources/Supabase/phase_final_admin_suspend.sql`

Run `phase_final_admin_suspend.sql` last.

## 1. Authentication And Profile

| ID | Actor | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| AUTH-01 | New user | Register with valid password, matching confirm password | Success alert appears, user returns to login | Not tested |
| AUTH-02 | New user | Register with weak password | Password validation error appears | Not tested |
| AUTH-03 | Citizen A | Login with correct credentials | Citizen home opens | Not tested |
| AUTH-04 | Citizen A | Logout | Login screen appears | Not tested |
| AUTH-05 | Citizen A | Edit profile name | Name updates and persists after refresh/login | Not tested |

## 2. Admin User Management

| ID | Actor | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| ADMIN-01 | Admin A | Open admin user list | All users are visible with role/status chips | Not tested |
| ADMIN-02 | Admin A | Promote Coordinator A to coordinator | Coordinator A appears as coordinator and can access coordinator views | Not tested |
| ADMIN-03 | Admin A | Try to change own admin role | App blocks the action | Not tested |
| ADMIN-04 | Admin A | Suspend Citizen C | Citizen C is marked Suspended/Blocked | Not tested |
| ADMIN-05 | Citizen C | Try to login after suspension | App blocks access and shows suspended account message | Not tested |
| ADMIN-06 | Admin A | Reactivate Citizen C | Citizen C can login again | Not tested |

## 3. Citizen Request Flow

| ID | Actor | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| CIT-01 | Citizen A | Create request using automatic GPS location | Request is created with coordinates and open status | Not tested |
| CIT-02 | Citizen A | Create request using manual coordinates | Request is created with manual latitude/longitude | Not tested |
| CIT-03 | Citizen A | Try empty description | Validation blocks submit | Not tested |
| CIT-04 | Citizen A | Try invalid latitude/longitude | Validation blocks submit | Not tested |
| CIT-05 | Citizen A | Open My Requests | Own requests are listed only | Not tested |
| CIT-06 | Citizen A | Open request detail | Status, urgency, priority, location, timeline shown | Not tested |
| CIT-07 | Citizen A | Update active request description/urgency/location | Request updates and activity is logged | Not tested |
| CIT-08 | Citizen A | Cancel active request | Status becomes cancelled; action buttons disappear | Not tested |

## 4. Evidence Upload

| ID | Actor | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| EVD-01 | Citizen A | Add evidence photo to own active request | Photo uploads and appears in Evidence list | Not tested |
| EVD-02 | Citizen A | Add up to 3 evidence photos | Limit is enforced after 3 photos | Not tested |
| EVD-03 | Citizen A | Try evidence on completed/cancelled request | Upload button is hidden or blocked | Not tested |
| EVD-04 | Citizen B as volunteer | Upload evidence to assigned active request | Upload succeeds | Not tested |
| EVD-05 | Unrelated citizen | Try to view/upload evidence for unrelated request | RLS blocks access | Not tested |

## 5. Nearby Request And Volunteer Flow

| ID | Actor | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| VOL-01 | Citizen B | Open Nearby Requests after Citizen A creates request | Request appears after refresh/polling | Not tested |
| VOL-02 | Citizen B | Accept Citizen A's request | Citizen B becomes volunteer/busy; request becomes confirmed | Not tested |
| VOL-03 | Citizen B | Open Tasks | Accepted task appears | Not tested |
| VOL-04 | Citizen B | Start response | Request moves to in_progress | Not tested |
| VOL-05 | Citizen B | Mark completed | Request becomes completed; Citizen B returns available/citizen when no active task remains | Not tested |
| VOL-06 | Citizen B | Try accepting second request while busy | App or Supabase blocks the action | Not tested |

## 6. Coordinator Dashboard

| ID | Actor | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| COORD-01 | Coordinator A | Open coordinator dashboard | Active request summary and list load | Not tested |
| COORD-02 | Coordinator A | Update request priority | Priority changes and log is created | Not tested |
| COORD-03 | Coordinator A | Update request status using valid transition | Status changes and log is created | Not tested |
| COORD-04 | Coordinator A | Try invalid status transition, if possible | DB/app blocks invalid transition | Not tested |
| COORD-05 | Coordinator A | Open volunteer coordination | Volunteer/task status is visible | Not tested |
| COORD-06 | Coordinator A | Log supply/resource support | Supply action appears in recent support list | Not tested |
| COORD-07 | Coordinator A | Publish emergency announcement | Announcement appears for selected audience | Not tested |
| COORD-08 | Coordinator A | Use coordinator map filters | Map/list filters by urgency/status/type/location | Not tested |

## 7. Suspicious Activity And Admin Moderation

| ID | Actor | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| REP-01 | Citizen A | Submit suspicious activity report with selected request | Report is created and visible in own report list | Not tested |
| REP-02 | Citizen B/Volunteer | Submit suspicious activity report | Report is created | Not tested |
| REP-03 | Coordinator A | Submit suspicious activity report | Report is created | Not tested |
| REP-04 | Admin A | Open moderation panel | Reports are visible | Not tested |
| REP-05 | Admin A | Move report to reviewing/resolved/dismissed | Status updates, moderation action and activity log are created | Not tested |
| REP-06 | Admin A | Cancel suspicious request from moderation flow | Request becomes cancelled | Not tested |

## 8. Notifications, Announcements, And Refresh

| ID | Actor | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| NOTIF-01 | Citizen A | Volunteer accepts request | Citizen A receives in-app notification after refresh/polling | Not tested |
| NOTIF-02 | Citizen A | Volunteer starts/completes task | Citizen A receives status notification | Not tested |
| NOTIF-03 | Admin A | Report submitted | Admin receives report notification | Not tested |
| NOTIF-04 | Citizen/Volunteer | Coordinator publishes announcement | Announcement appears for the selected audience | Not tested |
| NOTIF-05 | Any user | Mark notification read | Unread count decreases | Not tested |

## 9. Offline Cache Lite

| ID | Actor | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| CACHE-01 | Citizen A | Load My Requests once, then simulate network failure | Last saved list appears with orange offline cache banner | Not tested |
| CACHE-02 | Citizen B | Load Nearby Requests once, then simulate network failure | Cached nearby list appears with warning banner | Not tested |
| CACHE-03 | Citizen/Volunteer | Load Request Detail once, then simulate network failure | Cached detail appears with warning banner | Not tested |
| CACHE-04 | Any user | Try create/update while offline | Action fails; app does not pretend offline write succeeded | Not tested |

## 10. RLS And Negative Security Checks

| ID | Actor | Steps | Expected Result | Status |
| --- | --- | --- | --- | --- |
| RLS-01 | Citizen B | Try to update Citizen A's request | Supabase blocks update | Not tested |
| RLS-02 | Citizen B | Try to cancel Citizen A's request | Supabase blocks update | Not tested |
| RLS-03 | Citizen A | Try to accept own request | Supabase blocks action | Not tested |
| RLS-04 | Citizen/Volunteer | Try to change own role directly through profile settings | App has no direct role change path; DB blocks unauthorized role changes | Not tested |
| RLS-05 | Non-admin | Try to access admin/coordinator screens through normal navigation | No access from role-based UI | Not tested |
| RLS-06 | Suspended user | Try existing session restore | User is signed out / blocked from app | Not tested |

## Demo Pass Criteria

The app is ready for final demo when:

- All critical tests pass: AUTH-03, ADMIN-02, ADMIN-04, ADMIN-05, CIT-01, CIT-05, CIT-06, EVD-01, VOL-01, VOL-02, VOL-04, VOL-05, COORD-01, COORD-02, COORD-06, COORD-07, REP-01, REP-04, NOTIF-01.
- No role sees screens or data outside its permission boundary.
- No critical flow depends on offline cache as confirmed data.
- Evidence upload works against the real Supabase bucket.
- Build succeeds before demo.

