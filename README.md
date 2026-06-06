# UrbanShield

UrbanShield is an iOS disaster coordination prototype developed as a university graduation project. The application is designed for situations such as earthquakes, fires, floods, accidents, and medical emergencies where citizens may need structured community assistance before official response teams can fully reach the area.

The project provides a centralized mobile workflow for creating help requests, viewing nearby incidents, accepting volunteer tasks, coordinating emergency operations, moderating users, and reviewing suspicious activity reports.

## Project Summary

UrbanShield solves the coordination problem that appears when emergency information is scattered across phone calls, messaging groups, and social media posts. In those channels, requests can be duplicated, outdated, unverified, or missed. UrbanShield organizes this information into database-backed request records with clear status, location, user ownership, volunteer assignment, and coordinator/admin oversight.

Main goals:

- Citizens can create, update, cancel, and track emergency help requests.
- A citizen can become an active volunteer by accepting or being assigned to a request.
- Active volunteers can start response, cancel before response starts, and mark tasks as completed.
- Coordinators can monitor active requests, update status, assign volunteers, record support actions, and publish announcements.
- Administrators can manage users, roles, suspensions, suspicious reports, and activity logs.
- The system uses Supabase Auth, PostgreSQL, Row Level Security, RPC functions, Supabase Storage, Apple MapKit, CoreLocation, and SwiftUI.

## Technology Stack

- Platform: iOS
- Language: Swift
- UI framework: SwiftUI
- Local architecture: MVVM
- Backend platform: Supabase
- Database: PostgreSQL
- Authentication: Supabase Auth
- Authorization: Role-Based Access Control in the app plus PostgreSQL Row Level Security
- Sensitive backend operations: PostgreSQL RPC functions
- Maps and location: Apple MapKit and CoreLocation
- Evidence photos: PhotosUI plus Supabase Storage
- Refresh strategy: Supabase Realtime where available, with lightweight polling fallback in selected screens

## Architecture

The application follows an MVVM-style structure:

- `View`: SwiftUI screens and reusable UI components.
- `ViewModels`: screen state, validation, Supabase calls, loading/error/success feedback, and user actions.
- `Domain`: app-facing user/session models.
- `Core`: shared services such as Supabase client, authentication, location, realtime refresh, errors, and keyboard behavior.
- `Resources/Supabase`: SQL migration and policy files used in Supabase SQL Editor.

The project intentionally keeps backend calls inside ViewModels and Core services because this is the implementation direction chosen during development. Earlier DTO/repository/use-case layers were not used in the final project.

## Main Folder Map

| Folder | Purpose |
| --- | --- |
| `UrbanShield/App` | App entry point, root routing, and high-level navigation decisions. |
| `UrbanShield/Core` | Supabase client, auth service, location service, realtime helper, app errors, and shared UI modifiers. |
| `UrbanShield/Domain` | User, role, and session models used across the app. |
| `UrbanShield/View` | SwiftUI screens grouped by feature: auth, home, profile, requests, coordinator, admin, reports, notifications, announcements. |
| `UrbanShield/ViewModels` | Screen-specific state and business logic. These files contain most Supabase queries and RPC calls. |
| `UrbanShield/Resources/Supabase` | SQL files for tables, RLS policies, RPC functions, storage metadata, notifications, logs, and fixes. |

## User Roles and Access

UrbanShield has three main long-term roles in the final implementation: citizen, coordinator, and admin.

Volunteer behavior is implemented as an operational state of a citizen. A citizen becomes an active volunteer when they accept or are assigned to a help request. When the task is completed, cancelled, or released, that user returns to available citizen state.

Role behavior:

- Citizen: create own help request, view own requests, update allowed fields, cancel eligible requests, view nearby requests, accept a suitable request as volunteer, submit suspicious reports.
- Active Volunteer: start response, cancel confirmed task before response starts, upload evidence for assigned task, complete in-progress task.
- Coordinator: monitor active requests, update request status, assign volunteers, view maps and filters, record supply/support actions, publish announcements.
- Admin: manage users, roles, suspensions, suspicious reports, moderation decisions, and activity logs.

## Request Lifecycle

Help requests move through these states:

1. `open`: created by a citizen and visible to nearby users/coordinators.
2. `confirmed`: at least one volunteer accepted or was assigned.
3. `in_progress`: a volunteer started response.
4. `completed`: assistance task was completed.
5. `cancelled`: request was cancelled or terminated.

Important rules:

- A citizen can update only their own editable requests.
- Completed and cancelled requests are no longer editable.
- A volunteer must be available and must have matching skills before accepting.
- A busy volunteer cannot accept another active task.
- Critical requests can support multiple active volunteers; lower urgency requests generally allow one active volunteer.
- Coordinator status changes and volunteer assignments use RPC functions because they affect multiple database records.

## Database Overview

Main tables used by the app:

- `profiles`: user profile, role, availability, volunteer skills, suspension state.
- `help_requests`: citizen-created emergency requests.
- `help_request_volunteers`: assignment records between requests and active volunteers.
- `request_evidence`: metadata for uploaded evidence photos.
- `notifications`: in-app notification records.
- `emergency_announcements`: coordinator/admin announcements.
- `suspicious_activity_reports`: user-submitted suspicious activity reports.
- `coordination_logs`: coordinator status/assignment/support logs.
- `activity_logs`: admin and system-level trace records.

Sensitive workflows are implemented with SQL RPC functions so the database can enforce consistency:

- Accepting a request as volunteer.
- Completing a volunteer task.
- Cancelling a confirmed volunteer task.
- Updating request status as coordinator.
- Assigning a volunteer as coordinator.
- Creating request evidence metadata after storage upload.
- Suspending or reactivating users.

## Security Model

Security is applied in two layers:

1. App-side role checks hide or disable screens and actions that the current user should not use.
2. Supabase/PostgreSQL Row Level Security and RPC functions enforce authorization at the database level.

This means UI restrictions improve usability, but the database remains the final authority. If a user tries to perform a forbidden operation from the client, the database should reject it.

## Key Swift Files

### App and Routing

- `UrbanShield/App/UrbanShieldApp.swift`: app entry point.
- `UrbanShield/App/RootView.swift`: restores session and decides whether to show auth flow or authenticated app.
- `UrbanShield/App/AppRouter.swift`: high-level app route definitions.
- `UrbanShield/View/ContentView.swift`: role-based content entry point.

### Authentication and Profile

- `UrbanShield/Core/AuthService.swift`: all Supabase Auth and profile operations.
- `UrbanShield/ViewModels/Auth/AuthSessionViewModel.swift`: current session state, auth redirect handling, sign out, account deletion.
- `UrbanShield/ViewModels/Auth/LoginViewModel.swift`: login form state and error handling.
- `UrbanShield/ViewModels/Auth/RegisterViewModel.swift`: registration form state, password validation, and success feedback.
- `UrbanShield/View/Profile/ProfileView.swift`: profile overview.
- `UrbanShield/View/Profile/ProfileSettingsView.swift`: profile editing, volunteer availability, skills, sign out, and account actions.

### Help Requests

- `UrbanShield/ViewModels/Requests/RequestSharedTypes.swift`: request enums, request records, assignment records, evidence records, and lifecycle helpers.
- `UrbanShield/ViewModels/Requests/CreateRequestViewModel.swift`: request creation validation and insert into `help_requests`.
- `UrbanShield/View/Requests/Views/CreateRequestView.swift`: modern request creation UI with request type, urgency, description, map/manual location input.
- `UrbanShield/ViewModels/Requests/MyRequestsViewModel.swift`: loads current citizen's own submitted requests.
- `UrbanShield/View/Requests/Views/MyRequestsView.swift`: own request list and filters.
- `UrbanShield/ViewModels/Requests/NearbyRequestsViewModel.swift`: loads active nearby requests, filters full/busy requests, accepts request via RPC, realtime/polling refresh.
- `UrbanShield/View/Requests/Views/NearbyRequestsView.swift`: map/list screen for available requests.
- `UrbanShield/ViewModels/Requests/RequestDetailViewModel.swift`: request detail, update, cancel, evidence upload, volunteer start/complete/cancel, coordinator status, coordinator assignment.
- `UrbanShield/View/Requests/Views/RequestDetailView.swift`: detail UI, lifecycle display, evidence UI, coordinator controls, citizen and volunteer action buttons.
- `UrbanShield/ViewModels/Requests/VolunteerTasksViewModel.swift`: loads current user's active volunteer tasks.
- `UrbanShield/View/Requests/Views/VolunteerTasksView.swift`: task list shown to active volunteers.

### Maps and Location

- `UrbanShield/Core/DeviceLocationService.swift`: permission request and current GPS location retrieval.
- `UrbanShield/View/Requests/Views/MapCoordinatePickerView.swift`: map-based coordinate picker.
- `UrbanShield/ViewModels/Coordinator/CoordinatorMapViewModel.swift`: coordinator map data and filters.
- `UrbanShield/View/Coordinator/CoordinatorMapView.swift`: coordinator map interface.

### Coordinator

- `UrbanShield/ViewModels/Coordinator/CoordinatorDashboardViewModel.swift`: coordinator request list, sorting, status update, volunteer assignment, logs, realtime.
- `UrbanShield/View/Coordinator/CoordinatorDashboardView.swift`: coordinator dashboard UI.
- `UrbanShield/ViewModels/Coordinator/CoordinatorOperationsViewModel.swift`: support/resource action records.
- `UrbanShield/View/Coordinator/CoordinatorOperationsView.swift`: coordination tools and support actions.
- `UrbanShield/ViewModels/Coordinator/VolunteerCoordinationViewModel.swift`: volunteer availability/skill monitoring.
- `UrbanShield/View/Coordinator/VolunteerCoordinationView.swift`: volunteer coordination dashboard.
- `UrbanShield/View/Home/CoordinatorHomeView.swift`: coordinator tab/home shell.

### Admin and Moderation

- `UrbanShield/ViewModels/Admin/AdminUserManagementViewModel.swift`: user list, role update, suspend/reactivate.
- `UrbanShield/View/Admin/AdminUserManagementView.swift`: admin user management UI.
- `UrbanShield/ViewModels/Admin/AdminModerationViewModel.swift`: suspicious report moderation.
- `UrbanShield/View/Admin/AdminModerationView.swift`: moderation UI.
- `UrbanShield/ViewModels/Admin/AdminActivityLogViewModel.swift`: activity log filtering/loading.
- `UrbanShield/View/Admin/AdminActivityLogView.swift`: activity log UI.
- `UrbanShield/View/Home/AdminHomeView.swift`: admin tab/home shell.

### Notifications, Announcements, Reports

- `UrbanShield/ViewModels/Shared/InAppNotificationService.swift`: inserts notification rows for relevant users.
- `UrbanShield/ViewModels/Notifications/NotificationsViewModel.swift`: loads, marks, and refreshes notifications.
- `UrbanShield/View/Notifications/NotificationsView.swift`: notification inbox UI.
- `UrbanShield/ViewModels/Announcements/EmergencyAnnouncementsViewModel.swift`: announcement create/load logic.
- `UrbanShield/View/Announcements/EmergencyAnnouncementsView.swift`: alerts/announcements screen.
- `UrbanShield/ViewModels/Reports/SuspiciousActivityReportViewModel.swift`: suspicious activity report creation.
- `UrbanShield/View/Reports/SuspiciousActivityReportView.swift`: report submission UI.

### Shared Support

- `UrbanShield/ViewModels/Shared/ActivityLogger.swift`: central activity log insert helper.
- `UrbanShield/ViewModels/Shared/OfflineCacheStore.swift`: small local cache fallback for selected data.
- `UrbanShield/Core/Realtime/RealtimeRefreshSubscription.swift`: reusable Supabase Realtime subscription wrapper.
- `UrbanShield/Core/UI/KeyboardDismissOnTapModifier.swift`: dismisses keyboard when tapping outside inputs.

## Supabase SQL Files

SQL files are stored in `UrbanShield/Resources/Supabase`.

Run these files in order:

- `01_auth_profiles.sql`: profiles, roles, availability, and profile RLS.
- `02_requests_assignments.sql`: help requests, volunteer assignments, request RLS.
- `03_request_workflow_rpc.sql`: request lifecycle, volunteer accept/complete/cancel, coordinator assignment/status, admin suspension.
- `04_evidence_storage.sql`: evidence metadata, Storage bucket, Storage/RLS policies.
- `05_operations_moderation.sql`: coordinator logs, supply support, announcements, suspicious reports, moderation.
- `06_notifications_logs.sql`: activity logs, in-app notifications, notification RPCs, realtime publication.
- `07_permissions.sql`: authenticated role grants for tables and functions.

## Main User Flows

### Citizen Creates Request

1. User signs in.
2. Opens Create Request.
3. App gets GPS location if possible or lets user enter/select coordinates manually.
4. User selects type and urgency, writes description, submits.
5. `CreateRequestViewModel` validates input.
6. A row is inserted into `help_requests`.
7. Activity log is inserted.
8. If request is critical, coordinator/admin notification is created.

### Citizen Accepts Request as Active Volunteer

1. User opens Nearby Requests.
2. `NearbyRequestsViewModel` loads active requests excluding the user's own requests.
3. It checks active assignment count and request capacity.
4. User taps accept.
5. ViewModel checks availability and skills.
6. RPC `accept_help_request_as_volunteer` creates assignment, marks user busy, and updates request status.
7. Citizen who created the request receives in-app notification.

### Volunteer Starts and Completes Task

1. Active volunteer opens request detail.
2. If status is `confirmed`, button starts response and moves assignment/request to `in_progress`.
3. If status is `in_progress`, completion uses RPC `complete_my_volunteer_task`.
4. Assignment/request are updated and volunteer availability is released when appropriate.
5. Citizen receives notification.

### Coordinator Assigns Volunteer

1. Coordinator opens dashboard or request detail.
2. App loads active requests, available volunteers, and active volunteer counts.
3. Coordinator chooses a matching available volunteer.
4. RPC `coordinator_assign_volunteer_to_request` creates assignment, marks volunteer busy, and updates request if needed.
5. Coordination log, activity log, and notifications are created.

### Admin Suspends User

1. Admin opens user management.
2. Admin suspends selected user.
3. Backend updates profile suspension state.
4. If user is an active volunteer, their assignment is released and request capacity becomes available again.
5. Suspended user is blocked from active operations.

## Common Jury Modification Guide

If asked to change request statuses:

- Swift enums: `UrbanShield/ViewModels/Requests/RequestSharedTypes.swift`
- Detail logic: `UrbanShield/ViewModels/Requests/RequestDetailViewModel.swift`
- Coordinator logic: `UrbanShield/ViewModels/Coordinator/CoordinatorDashboardViewModel.swift`
- Database/RLS/RPC: `UrbanShield/Resources/Supabase`

If asked to change volunteer capacity:

- Swift capacity helper: `HelpRequestUrgency.volunteerCapacity` in `RequestSharedTypes.swift`
- Nearby list filtering: `NearbyRequestsViewModel.swift`
- Coordinator assignment checks: `CoordinatorDashboardViewModel.swift` and `RequestDetailViewModel.swift`
- SQL functions: priority/capacity SQL files in `Resources/Supabase`

If asked to change request creation fields:

- UI: `CreateRequestView.swift`
- Validation/insert payload: `CreateRequestViewModel.swift`
- Database columns/RLS: `Resources/Supabase`

If asked to change evidence upload:

- UI: `RequestDetailView.swift`
- Upload/compression/metadata: `RequestDetailViewModel.swift`
- Storage bucket and policies: `04_evidence_storage.sql`

If asked to change login/register behavior:

- UI: `LoginView.swift`, `RegisterView.swift`
- State and validation: `LoginViewModel.swift`, `RegisterViewModel.swift`
- Supabase Auth/profile: `AuthService.swift`

If asked to change admin/coordinator permissions:

- App-side role checks: related ViewModel guards.
- Database authority: RLS policies and RPC functions in `Resources/Supabase`.

## Manual Demo Checklist

1. Register a citizen account and verify success feedback.
2. Login as citizen.
3. Create a request with GPS/manual coordinates.
4. Open My Requests and verify the request appears.
5. Login as another citizen with volunteer skills and availability.
6. Open Nearby Requests and accept the request.
7. Verify volunteer becomes busy and cannot accept another active request.
8. Start response and complete the task.
9. Verify request status becomes completed and volunteer becomes available again.
10. Login as coordinator and verify dashboard, map, status update, volunteer assignment, and support action screens.
11. Create an emergency announcement and verify user alert visibility.
12. Submit a suspicious activity report from a non-admin user.
13. Login as admin and verify user management, report moderation, suspension/reactivation, and activity logs.

## Known Implementation Decisions

- Volunteer is not treated as a separate permanent role in the final app flow. It is an active state of a citizen after accepting or being assigned to a task.
- In-app notifications are database-backed app notifications, not full Apple Push Notification Service delivery.
- Realtime behavior uses Supabase Realtime where available and lightweight polling fallback on selected screens to stay practical for the free/demo environment.
- DTO/repository/use-case layers were not used in the final implementation; Supabase calls live in ViewModels and shared Core services.

## Build Notes

Open the project in Xcode and run the UrbanShield iOS target on an iPhone simulator or physical iPhone. Supabase project URL, API key, database tables, storage bucket, RLS policies, and RPC functions must be configured before testing backend flows.
