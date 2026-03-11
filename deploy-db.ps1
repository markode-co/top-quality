# =========================================
# Supabase Full Migration Deploy Script
# =========================================

Write-Host "Starting migration validation..."

# التأكد من تسجيل الدخول
supabase login

# ربط المشروع
supabase link --project-ref YOUR_PROJECT_ID

# فحص حالة قاعدة البيانات
supabase db diff

# التحقق من المايغريشن
Write-Host "Checking migrations..."
supabase migration list

# تشغيل جميع المايغريشن
Write-Host "Applying migrations..."
supabase db push

# تأكيد الحالة
Write-Host "Final database status:"
supabase db status

Write-Host "All migrations deployed successfully"