# UrbanShield Stabilization, RLS Review, and RAD/SDD Gap Check

Date: 2026-05-20

## Scope

This check covers three stabilization items:

- Offline cache lite for read-only screens.
- RLS/security review for the Supabase SQL currently kept in the repository.
- Final RAD/SDD gap check based on `RAD_22COMP1012_21COMP1030_22SOFT1052.pdf` and `SDD.pdf`.

## Offline Cache Lite

Implemented as a view-only fallback with `UserDefaults` JSON storage through `OfflineCacheStore`.

Cached screens:

- My Requests
- Nearby Requests
- Volunteer Tasks
- Request Detail
- Notifications
- Emergency Announcements

Behavior:

- Successful network fetches save the latest result locally.
- If a fetch fails, the screen can show the last cached result with an orange warning banner.
- Mutating flows are not cached as successful operations. Create, update, cancel, accept, complete, report, announcement, and moderation actions still require Supabase.

RAD/SDD alignment:

- RAD UC-4.2 describes viewing cached request data when network access is weak.
- SDD states cached content may be used for non-critical viewing, but request allocation, updates, and moderation must not treat cached data as confirmed state.
- This implementation follows that boundary by limiting cache use to read-only UI fallback.

## RLS/Security Review

Reviewed repository SQL files under:

- `Supabase/request_assignment_flow.sql`
- `UrbanShield/Resources/Supabase/*.sql`

Main finding fixed:

- `phase5_2_in_app_notifications.sql` previously allowed broad authenticated direct notification inserts.
- Direct inserts are now ownership-scoped: a user can only insert their own notification row and actor must be null or the signed-in user.
- Cross-user notification creation now goes through `create_in_app_notifications(...)`, which validates signed-in access, title/message, category, link type, actor ownership, and recipient existence.

Important SQL dependency:

- `create_in_app_notifications(...)` uses `public.current_app_role()`.
- `current_app_role()` is defined in `phase3_1_coordinator_status_logs.sql`.
- Run the Phase 3 SQL before or along with the updated Phase 5.2 notification SQL.

Remaining production hardening notes:

- Client-triggered notification RPCs are acceptable for this project phase, but a production system would preferably create system notifications from trusted backend code, database triggers, or Edge Functions.
- RLS should still be tested with separate citizen, volunteer, coordinator, and admin accounts in the live Supabase project because repository SQL can drift from the actual database state.
- Role changes are intentionally guarded by database functions/triggers. Admin/coordinator role changes should remain inside the approved admin flow or trusted SQL, not random profile updates from the client.

## RAD/SDD Feature Coverage

Covered or mostly covered:

- User registration, login, logout, session routing, and role-based home screens.
- Citizen request creation, detail, list, cancel, update, evidence upload, GPS/current location, manual coordinates, map selection, nearby request map.
- Volunteer availability, skills, accepting requests, task dashboard, start/in-progress flow, completion flow, and status release after completed/cancelled/deleted assignments.
- Coordinator dashboard, request priority/status management, coordination logs, volunteer coordination, supply/resource actions, announcements, map, and filters.
- Suspicious activity reports for citizen, volunteer, and coordinator; admin moderation for reports.
- Admin user list, role assignment flow, and soft account suspension/reactivation.
- Activity logs and activity filtering.
- In-app notifications with realtime/polling refresh.
- Offline cache lite for low-network read-only screens.

Partial or not yet implemented:

- Local/push notifications are not implemented. Current notification system is in-app only.
- Offline cache does not queue writes or sync offline actions later.
- Evidence upload exists with app-side compression, 1 MB file guard, bucket SQL, RLS policies, and database file constraints. The real Supabase bucket/policy flow should still be tested before final demo.
- RAD mentions volunteer supply support in addition to coordinator supply coordination. Current implementation is coordinator-focused.
- Admin moderation and account suspension exist. Full hard-delete of other users is intentionally not implemented in-app because it usually requires a trusted server/admin API path.
- Realtime behavior is intentionally cost-conscious and combined with polling. It is not a full high-frequency realtime system.

## Recommended Manual Test Matrix

Use at least four test accounts:

- Citizen A
- Citizen B
- Volunteer/current accepted helper
- Coordinator
- Admin

Minimum checks:

- Citizen A creates a request with current GPS, manual fallback, and evidence photo.
- Citizen B sees the request on Nearby Requests after refresh/polling and can accept it.
- Accepted helper becomes busy while assigned, can move request through in-progress and completed, and is released after completion.
- Coordinator can update priority/status, add coordination log, add supply action, and publish an announcement.
- Citizen/Volunteer/Coordinator can submit suspicious activity report; Admin can view and moderate it.
- Admin can suspend a non-admin/current user, the suspended user cannot continue into the app after login/session restore, then Admin can reactivate the account.
- Notifications appear for relevant users after refresh/polling.
- Turn network off or force Supabase fetch failure, then verify cached read-only screens show previous data with warning banners.
- Verify direct unauthorized changes fail: citizen cannot edit another user's request, non-admin cannot change arbitrary profile role, and users cannot view another user's notifications.
