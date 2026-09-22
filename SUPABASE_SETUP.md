# Connect CrewMatch to Supabase

1. Create a free project at https://supabase.com/dashboard.
2. Open **SQL Editor**, create a new query, paste `supabase.sql`, and click **Run**.
3. Open **Project Settings → API**.
4. Copy:
   - Project URL
   - Publishable/anon key
5. Add the Site URL under **Authentication → URL Configuration**:
   `https://batan25792579-ship-it.github.io/CrewMatch/`

Only the Project URL and publishable/anon key belong in the browser application. Never commit the service-role key or database password.

The schema enforces 18+, prevents private messages without a mutual match, and applies block rules at database level.
