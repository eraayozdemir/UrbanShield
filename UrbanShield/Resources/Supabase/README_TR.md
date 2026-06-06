# UrbanShield Supabase SQL Kurulumu

Bu klasördeki SQL dosyaları UrbanShield veritabanını, tablolarını, RLS policy kurallarını, RPC fonksiyonlarını, Storage ayarlarını ve realtime publication ayarlarını oluşturur.

Dosyaları Supabase SQL Editor içinde aşağıdaki sırayla çalıştırın:

1. `01_auth_profiles.sql`
2. `02_requests_assignments.sql`
3. `03_request_workflow_rpc.sql`
4. `04_evidence_storage.sql`
5. `05_operations_moderation.sql`
6. `06_notifications_logs.sql`
7. `07_permissions.sql`

## Dosya Açıklamaları

- `01_auth_profiles.sql`: `profiles` tablosu, kullanıcı rolleri, availability durumu ve temel profile RLS kuralları.
- `02_requests_assignments.sql`: `help_requests` ve `help_request_volunteers` tabloları, request görüntüleme/insert/update RLS kuralları.
- `03_request_workflow_rpc.sql`: request lifecycle, volunteer accept/start/complete/cancel, coordinator status update, coordinator assignment ve admin suspend RPC fonksiyonları.
- `04_evidence_storage.sql`: `request_evidence` tablosu, Supabase Storage `request-evidence` bucket ayarı ve evidence RLS kuralları.
- `05_operations_moderation.sql`: coordinator logs, supply support actions, emergency announcements, suspicious activity reports ve moderation actions tabloları.
- `06_notifications_logs.sql`: `activity_logs`, `notifications`, notification RPC fonksiyonları ve realtime publication ayarları.
- `07_permissions.sql`: authenticated role için gerekli table/function grant izinleri.

## Notlar

- SQL dosyaları idempotent yazılmıştır; çoğu bölüm tekrar çalıştırılabilir.
- Gerçek erişim kontrolü RLS policy ve RPC fonksiyonlarıyla yapılır.
- `profiles.id`, Supabase Auth içindeki `auth.users.id` ile aynıdır.
- Volunteer, uygulamada citizen kullanıcının aktif operasyonel durumu gibi çalışır.
- Critical requestler 3 active volunteer kabul edebilir; diğer urgency seviyeleri 1 volunteer kabul eder.
- Evidence upload için Supabase Storage içinde `request-evidence` bucket kullanılır.

