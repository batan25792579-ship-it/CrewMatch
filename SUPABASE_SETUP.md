# CrewMatch: подключение Supabase и проверка двух аккаунтов

Сайт: https://batan25792579-ship-it.github.io/CrewMatch/

## 1. Подготовьте базу данных

Откройте свой проект в https://supabase.com/dashboard → **SQL Editor**.

- Если таблицы CrewMatch ещё не создавались: один раз выполните [supabase.sql](supabase.sql), затем [supabase-profile-gate.sql](supabase-profile-gate.sql).
- Если ранее запускали старый `supabase.sql`, где дата рождения хранилась в `public.profiles`: сначала выполните [supabase-privacy-migration.sql](supabase-privacy-migration.sql), затем [supabase-profile-gate.sql](supabase-profile-gate.sql).
- Если таблица `public.profile_private` уже есть **и столбца `public.profiles.birth_date` больше нет**, выполните только [supabase-profile-gate.sql](supabase-profile-gate.sql). Не запускайте базовый `supabase.sql` повторно.

Для быстрой проверки в SQL Editor:

```sql
select to_regclass('public.profiles') as public_profiles,
       to_regclass('public.profile_private') as private_birth_dates,
       exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'profiles'
                 and column_name = 'birth_date') as birth_date_still_public;
```

После защитной миграции функция `public.save_crew_profile` создаёт публичный профиль и закрытую дату рождения в одной транзакции. Сайт проверяет функцию `public.crewmatch_setup_status` и **не создаёт учётные записи и анкеты, пока миграция не выполнена**. После запуска SQL нажмите **Connect → Setup → Save connection** ещё раз: должен появиться статус **Database ready for crew accounts**. Прямое создание анкеты через клиентскую таблицу заблокировано; отметку `is_verified` пользователь самостоятельно установить не может. Возраст определяется по введённой дате рождения: документы и реальное место работы пока не проверяются.

## 2. Настройте вход

1. В Supabase откройте **Project Settings → API** (в некоторых версиях интерфейса **Connect → API Keys**). Скопируйте **Project URL** и **Publishable** / **anon** key.
2. Добавьте адрес сайта в **Authentication → URL Configuration**: `https://batan25792579-ship-it.github.io/CrewMatch/`.
3. Откройте сайт и нажмите **Connect → Setup**. Введите Project URL и Publishable key. На каждом браузере подключение сохраняется отдельно. Вводите только публичный ключ; Secret / service_role key и пароль базы в браузере запрещены.
4. Создайте учётную запись или войдите. Если Supabase просит подтвердить адрес почты, откройте ссылку из письма, затем войдите на сайте.

Если при сохранении подключения появляется **Project check failed**, проверьте URL, публичный ключ и выполнение SQL из шага 1.

## 3. Проверьте двух пользователей

1. Откройте сайт в двух независимых браузерах (например, Edge на ПК и браузер Android). В обоих введите одинаковые Project URL и Publishable key.
2. Зарегистрируйте два **разных** email-адреса и заполните две анкеты совершеннолетних. Укажите одинаковое название судна, если хотите проверить вкладку **Ship**. Судно можно добавить позднее через **Profile → Edit profile**.
3. Нажмите **Refresh** на вкладке **Discover** каждого пользователя. A ставит лайк B, затем B ставит лайк A: у B должно появиться совпадение с кнопкой личного сообщения.
4. A открывает **Matches → Refresh**, затем открывает B. Обменяйтесь сообщениями, обновите страницы и убедитесь, что история сохранилась.
5. Проверьте **Global Chat**: сообщение A должно быть видно B. **Log out** позволяет переключить аккаунт на одном устройстве.

В текущем MVP работает один общий чат. Значок онлайн, отдельные чаты по судну, проверка трудоустройства и скрытие названия судна от запросов к API ещё не реализованы; не считайте данные `ship_name` конфиденциальными.
