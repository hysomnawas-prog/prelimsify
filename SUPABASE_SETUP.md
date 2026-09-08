# Prelimsify Supabase setup

1. In Supabase Authentication -> Providers -> Email, turn **Confirm email OFF** for username-only login.
2. Run the complete `supabase_schema.sql` in Supabase SQL Editor.
3. Existing Auth users are repaired automatically by `ensure_my_profile()` when they log in.
4. New users are automatically given a `profiles` row by the `on_auth_user_created` trigger.
5. To make the first administrator, after the admin account exists run:

```sql
UPDATE public.profiles
SET role='admin', can_use_app=true
WHERE lower(username)='hysomnawas';
```

6. GitHub Pages must contain the files from this ZIP. Database SQL alone cannot update the website UI/JavaScript.

Passwords are handled by Supabase Auth and are never stored/displayed as plaintext in `profiles`.
