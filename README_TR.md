# UrbanShield

UrbanShield, üniversite bitirme projesi olarak geliştirilmiş bir iOS afet koordinasyon prototipidir. Uygulama; deprem, yangın, sel, büyük kaza ve tıbbi acil durumlarda vatandaşların yardım taleplerini daha düzenli biçimde oluşturmasını, gönüllülerin bu taleplere yanıt vermesini, coordinator kullanıcıların süreci yönetmesini ve admin kullanıcıların sistemi denetlemesini amaçlar.

## Projenin Amacı

Acil durumlarda bilgiler genellikle telefon görüşmeleri, sosyal medya paylaşımları veya mesajlaşma grupları üzerinden dağınık şekilde paylaşılır. Bu durum yardım taleplerinin kaybolmasına, tekrar etmesine, güncelliğini yitirmesine veya doğrulanmasının zorlaşmasına neden olabilir.

UrbanShield bu problemi merkezi bir mobil platform ile çözmeyi hedefler. Her yardım talebi veritabanında yapılandırılmış bir kayıt olarak tutulur. Talebin tipi, açıklaması, aciliyet seviyesi, konumu, durumu, sahibi, gönüllü atamaları ve işlem geçmişi izlenebilir hale gelir.

## Temel Özellikler

- Citizen kullanıcı emergency help request oluşturabilir.
- Citizen kendi requestlerini görüntüleyebilir, uygun durumdaysa güncelleyebilir veya iptal edebilir.
- Citizen başka bir request kabul ettiğinde active volunteer durumuna geçebilir.
- Active volunteer response başlatabilir, response başlamadan önce task iptal edebilir veya task tamamlayabilir.
- Coordinator aktif requestleri izleyebilir, status değiştirebilir, volunteer atayabilir ve support action kaydı oluşturabilir.
- Coordinator emergency announcement yayınlayabilir.
- Admin kullanıcıları, rolleri, suspension/reactivation işlemlerini, suspicious report kayıtlarını ve activity logları yönetebilir.
- Requestler listede ve harita üzerinde görüntülenebilir.
- Requestlere evidence photo eklenebilir.
- In-app notification sistemi ile önemli olaylar kullanıcılara gösterilebilir.

## Kullanılan Teknolojiler

- Platform: iOS
- Dil: Swift
- UI Framework: SwiftUI
- Mimari: MVVM
- Backend: Supabase
- Veritabanı: PostgreSQL
- Authentication: Supabase Auth
- Authorization: Role-Based Access Control + PostgreSQL Row Level Security
- Hassas backend işlemleri: PostgreSQL RPC functions
- Harita ve konum: Apple MapKit + CoreLocation
- Fotoğraf seçimi: PhotosUI
- Dosya saklama: Supabase Storage
- Veri güncelleme: Supabase Realtime + seçili ekranlarda hafif polling fallback

## Mimari Yapı

Proje MVVM yapısına göre organize edilmiştir:

- `View`: SwiftUI ekranları ve UI componentleri.
- `ViewModels`: ekran state yönetimi, validation, Supabase query/RPC çağrıları, loading/error/success yönetimi.
- `Domain`: uygulama içinde kullanılan User, Role ve Session modelleri.
- `Core`: ortak servisler. Supabase client, AuthService, LocationService, Realtime helper, keyboard dismiss gibi yapılar burada bulunur.
- `Resources/Supabase`: Supabase SQL dosyaları, table/policy/RPC/storage düzenlemeleri.

Bu projede DTO, Repository ve UseCase katmanları kullanılmadı. Geliştirme sırasında alınan karara göre Supabase bağlantıları ViewModel ve Core service dosyalarında yönetildi.

## Klasör Yapısı

| Klasör | Açıklama |
| --- | --- |
| `UrbanShield/App` | Uygulama başlangıcı, RootView ve role göre yönlendirme. |
| `UrbanShield/Core` | Supabase client, auth, location, realtime, error ve ortak UI helper dosyaları. |
| `UrbanShield/Domain` | User, UserRole ve AppSession gibi temel domain modelleri. |
| `UrbanShield/View` | SwiftUI ekranları. Auth, profile, request, coordinator, admin, report, notification ekranları burada. |
| `UrbanShield/ViewModels` | Ekranların state ve business logic dosyaları. Supabase işlemlerinin büyük kısmı burada. |
| `UrbanShield/Resources/Supabase` | Supabase SQL, RLS policy ve RPC function dosyaları. |

## Rol Mantığı

UrbanShield içinde temel roller şunlardır:

- `citizen`
- `coordinator`
- `admin`

Volunteer davranışı final uygulamada citizen rolünün operasyonel alt durumu gibi uygulanmıştır. Yani bir citizen, başka bir request kabul ettiğinde veya coordinator tarafından atandığında active volunteer gibi davranır. Task tamamlandığında, iptal edildiğinde veya kullanıcı serbest bırakıldığında tekrar available citizen durumuna döner.

## Request Lifecycle

Help request kayıtları şu durumlar arasında ilerler:

1. `open`: Citizen tarafından oluşturulan yeni request.
2. `confirmed`: En az bir volunteer requesti kabul etti veya coordinator volunteer atadı.
3. `in_progress`: Volunteer response başlattı.
4. `completed`: Yardım görevi tamamlandı.
5. `cancelled`: Request iptal edildi veya sonlandırıldı.

Önemli kurallar:

- Citizen yalnızca kendi requestlerini güncelleyebilir.
- Completed ve cancelled requestler düzenlenemez.
- Volunteer request kabul etmek için available olmalıdır.
- Volunteer ilgili request type için uygun skill sahibi olmalıdır.
- Busy volunteer başka bir aktif request kabul edemez.
- Critical requestler birden fazla volunteer alabilir.
- Lower urgency requestler normalde tek volunteer kapasitesine sahiptir.
- Coordinator status update ve volunteer assignment gibi çoklu tablo etkileyen işlemler RPC ile yapılır.

## Veritabanı Yapısı

Ana tablolar:

- `profiles`: kullanıcı profili, rol, availability, volunteer skills, suspension bilgisi.
- `help_requests`: citizen tarafından oluşturulan yardım talepleri.
- `help_request_volunteers`: request-volunteer assignment kayıtları.
- `request_evidence`: Supabase Storage içindeki evidence photo dosyalarının metadata kayıtları.
- `notifications`: uygulama içi notification kayıtları.
- `emergency_announcements`: coordinator/admin tarafından yayınlanan duyurular.
- `suspicious_activity_reports`: kullanıcıların gönderdiği suspicious report kayıtları.
- `coordination_logs`: coordinator status, assignment ve support action kayıtları.
- `activity_logs`: admin ve sistem denetimi için genel işlem logları.

## Güvenlik Modeli

Güvenlik iki katmanda uygulanır:

1. SwiftUI/ViewModel tarafında role göre ekran ve buton kontrolleri yapılır.
2. Supabase/PostgreSQL tarafında RLS policy ve RPC function kontrolleri uygulanır.

UI tarafındaki kontroller kullanıcı deneyimi içindir. Asıl güvenlik sınırı veritabanı tarafındaki RLS ve RPC kurallarıdır.

## Önemli Swift Dosyaları

### App ve Routing

- `UrbanShieldApp.swift`: uygulama başlangıç noktası.
- `RootView.swift`: session restore yapar ve login/authenticated akışını belirler.
- `AppRouter.swift`: kullanıcı rolüne göre CitizenHome, CoordinatorHome veya AdminHome ekranına yönlendirir.

### Authentication ve Profile

- `AuthService.swift`: Supabase Auth ve profile işlemlerinin merkezi servisidir.
- `AuthSessionViewModel.swift`: uygulamanın mevcut session durumunu yönetir.
- `LoginViewModel.swift`: login form validation ve error mesajlarını yönetir.
- `RegisterViewModel.swift`: sign-up formu, çift şifre kontrolü ve şifre kurallarını yönetir.
- `ProfileView.swift`: profil özet ekranı.
- `ProfileSettingsView.swift`: profil düzenleme, availability, skills, sign out ve hesap işlemleri.

### Request Akışı

- `RequestSharedTypes.swift`: request type, urgency, status, request record, volunteer assignment ve evidence modelleri.
- `CreateRequestViewModel.swift`: request creation validation ve Supabase insert işlemi.
- `CreateRequestView.swift`: request oluşturma UI ekranı.
- `MyRequestsViewModel.swift`: citizen kullanıcının kendi requestlerini yükler.
- `MyRequestsView.swift`: kendi requestlerini listeleyen ekran.
- `NearbyRequestsViewModel.swift`: nearby active requestleri yükler, kapasite/busy kontrolü yapar ve request kabul RPC çağrısını yapar.
- `NearbyRequestsView.swift`: requestleri liste/konum filtresiyle gösteren ekran.
- `RequestDetailViewModel.swift`: request detail, update, cancel, evidence upload, volunteer start/complete/cancel ve coordinator controls işlemlerini yönetir.
- `RequestDetailView.swift`: request detay UI ekranı.
- `VolunteerTasksViewModel.swift`: active volunteer tasklarını yükler.
- `VolunteerTasksView.swift`: volunteer task listesi.

### Coordinator

- `CoordinatorDashboardViewModel.swift`: request listesi, sorting, status update, volunteer assignment ve coordination log işlemleri.
- `CoordinatorDashboardView.swift`: coordinator dashboard UI ekranı.
- `CoordinatorOperationsViewModel.swift`: support/resource action kayıtlarını yönetir.
- `CoordinatorOperationsView.swift`: coordinator tools ve support action ekranı.
- `VolunteerCoordinationViewModel.swift`: volunteer durumlarını yükler.
- `VolunteerCoordinationView.swift`: volunteer coordination ekranı.
- `CoordinatorMapViewModel.swift`: coordinator map verilerini ve filtreleri yönetir.
- `CoordinatorMapView.swift`: coordinator harita ekranı.

### Admin

- `AdminUserManagementViewModel.swift`: kullanıcı listesi, role update, suspend/reactivate işlemleri.
- `AdminUserManagementView.swift`: admin user management UI.
- `AdminModerationViewModel.swift`: suspicious report review ve moderation action işlemleri.
- `AdminModerationView.swift`: admin moderation UI.
- `AdminActivityLogViewModel.swift`: activity log filtreleme ve yükleme.
- `AdminActivityLogView.swift`: activity log UI.

### Notifications, Announcements ve Reports

- `InAppNotificationService.swift`: notification kayıtlarını Supabase RPC ile oluşturur.
- `NotificationsViewModel.swift`: notification listesi ve okunma durumunu yönetir.
- `NotificationsView.swift`: notification inbox ekranı.
- `EmergencyAnnouncementsViewModel.swift`: announcement oluşturma ve listeleme.
- `EmergencyAnnouncementsView.swift`: alerts/announcement ekranı.
- `SuspiciousActivityReportViewModel.swift`: suspicious activity report oluşturma.
- `SuspiciousActivityReportView.swift`: report gönderme ekranı.

### Ortak Yardımcılar

- `ActivityLogger.swift`: activity_logs tablosuna merkezi log kaydı atar.
- `OfflineCacheStore.swift`: bazı ekranlar için UserDefaults tabanlı hafif offline cache sağlar.
- `RealtimeRefreshSubscription.swift`: Supabase Realtime eventlerini ekran refresh çağrısına bağlayan ortak helper.
- `DeviceLocationService.swift`: CoreLocation ile mevcut konumu alır.
- `KeyboardDismissOnTapModifier.swift`: ekranda boş alana dokununca klavyeyi kapatır.

## Supabase SQL Dosyaları

SQL dosyaları `UrbanShield/Resources/Supabase` altında tutulur.

Dosyaları Supabase SQL Editor içinde aşağıdaki sırayla çalıştırın:

- `01_auth_profiles.sql`: profil, rol, availability ve profil RLS yapısı.
- `02_requests_assignments.sql`: help request, volunteer assignment ve request RLS yapısı.
- `03_request_workflow_rpc.sql`: request lifecycle, volunteer accept/complete/cancel, coordinator assignment/status ve admin suspension RPC fonksiyonları.
- `04_evidence_storage.sql`: evidence metadata, Storage bucket ve Storage/RLS policy yapısı.
- `05_operations_moderation.sql`: coordination log, supply support, announcement, suspicious report ve moderation tabloları.
- `06_notifications_logs.sql`: activity log, in-app notification, notification RPC ve realtime publication ayarları.
- `07_permissions.sql`: authenticated rolü için gerekli tablo ve fonksiyon izinleri.

## Ana Kullanıcı Akışları

### Citizen Request Oluşturur

1. Citizen giriş yapar.
2. Create Request ekranını açar.
3. Request type, urgency, description ve location bilgilerini girer.
4. Uygulama GPS konumu alabilir veya kullanıcı manuel/map üzerinden koordinat seçebilir.
5. `CreateRequestViewModel` validation yapar.
6. `help_requests` tablosuna yeni kayıt eklenir.
7. Activity log oluşturulur.
8. Request critical ise coordinator/admin notification oluşturulur.

### Citizen Active Volunteer Olur

1. Başka bir citizen Nearby Requests ekranını açar.
2. Sistem kendi requestlerini, dolu requestleri ve kullanıcının kabul ettiği requestleri filtreler.
3. Kullanıcı uygun requesti kabul eder.
4. ViewModel availability ve skill kontrolü yapar.
5. RPC `accept_help_request_as_volunteer` çağrılır.
6. Assignment oluşturulur, kullanıcı busy olur, request confirmed olur.
7. Request sahibi notification alır.

### Volunteer Task Tamamlar

1. Active volunteer request detail ekranını açar.
2. Request confirmed ise Start Response yapar.
3. Request in_progress ise Mark Completed yapar.
4. Completion RPC request/assignment durumlarını günceller.
5. Volunteer availability tekrar available olur.
6. Citizen notification alır.

### Coordinator Volunteer Atar

1. Coordinator dashboard veya request detail ekranını açar.
2. Aktif requestleri, volunteer sayısını ve available volunteer listesini görür.
3. Uygun volunteer seçilir.
4. RPC `coordinator_assign_volunteer_to_request` çağrılır.
5. Assignment oluşturulur, volunteer busy olur.
6. Coordination log, activity log ve notification kayıtları oluşturulur.

### Admin Kullanıcıyı Suspend Eder

1. Admin User Management ekranını açar.
2. Kullanıcı suspend edilir.
3. Supabase RPC profile suspension durumunu günceller.
4. Kullanıcı active volunteer ise task boşa çıkarılır.
5. Request kapasitesi tekrar açılır.
6. Suspended user aktif işlemlerden engellenir.

## Jüri Modifikasyon Rehberi

Request status/type/urgency değişecekse:

- `RequestSharedTypes.swift`
- `RequestDetailViewModel.swift`
- `CoordinatorDashboardViewModel.swift`
- `Resources/Supabase` içindeki ilgili SQL dosyaları

Volunteer kapasitesi değişecekse:

- `HelpRequestUrgency.volunteerCapacity`
- `NearbyRequestsViewModel.swift`
- `CoordinatorDashboardViewModel.swift`
- `RequestDetailViewModel.swift`
- Supabase capacity/RPC SQL dosyaları

Request oluşturma formuna yeni alan eklenecekse:

- `CreateRequestView.swift`
- `CreateRequestViewModel.swift`
- `help_requests` SQL tablosu
- RLS/RPC gerekiyorsa `Resources/Supabase`

Evidence upload değişecekse:

- `RequestDetailView.swift`
- `RequestDetailViewModel.swift`
- `04_evidence_storage.sql`
- Supabase Storage bucket/policy ayarları

Login/Register değişecekse:

- `LoginView.swift`
- `RegisterView.swift`
- `LoginViewModel.swift`
- `RegisterViewModel.swift`
- `AuthService.swift`

Admin/coordinator yetkileri değişecekse:

- ilgili ViewModel guard kontrolleri
- Supabase RLS policies
- Supabase RPC functions

## Demo Checklist

1. Citizen hesabı oluştur.
2. Citizen olarak login ol.
3. GPS veya manuel koordinat ile request oluştur.
4. My Requests ekranında requesti gör.
5. Başka bir citizen hesabında volunteer skill/availability ayarla.
6. Nearby Requests ekranından request kabul et.
7. Kullanıcının busy olduğunu ve başka task alamadığını kontrol et.
8. Request detail ekranında Start Response yap.
9. Mark Completed yap.
10. Volunteer availability tekrar available oldu mu kontrol et.
11. Coordinator hesabında dashboard, map, status update ve assignment test et.
12. Announcement oluştur.
13. Suspicious report gönder.
14. Admin hesabında report moderation, user management, suspend/reactivate ve activity logları kontrol et.

## Önemli Tasarım Kararları

- Volunteer ayrı kalıcı rol gibi değil, citizen kullanıcının aktif operasyonel durumu gibi ele alındı.
- Notification sistemi APNs push yerine Supabase veritabanı tabanlı in-app notification olarak uygulandı.
- Realtime için Supabase Realtime kullanıldı; demo/free-plan güvenilirliği için bazı ekranlarda hafif polling fallback eklendi.
- Hassas işlemler doğrudan client update yerine RPC ile yapıldı.
- UI tarafındaki role kontrolleri kullanıcı deneyimi içindir; asıl güvenlik Supabase RLS ve RPC fonksiyonlarıdır.

## Build Notları

Projeyi Xcode içinde açıp UrbanShield target’ını iPhone Simulator veya fiziksel cihazda çalıştırabilirsiniz. Backend akışlarının çalışması için Supabase URL/key, tablolar, RLS policies, RPC functions ve Storage bucket doğru şekilde kurulmuş olmalıdır.
