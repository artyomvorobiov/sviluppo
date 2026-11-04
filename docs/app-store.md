# Карточка в App Store — готовые тексты и ответы

Всё, что App Store Connect спрашивает перед отправкой на проверку. Тексты можно вставлять как есть
(длина проверена по лимитам Apple). Где написано `<…>` — подставьте своё.

## App Information (левое меню → «Информация о приложении»)

| Поле | Что вписать |
|---|---|
| Name (до 30 символов) | `Квартет: искусство дня` (или ваше название — оно должно быть уникальным в App Store) |
| Subtitle (до 30) | `Картина, альбом, фильм, статья` |
| Primary Category | **Образование** (Education) |
| Secondary Category | **Развлечения** (Entertainment) |
| Content Rights | см. раздел «Права на контент» ниже |
| Age Rating | см. раздел «Возрастной рейтинг» ниже |

## Страница версии 1.0

**Promotional Text** (до 170, можно менять без новой проверки):

```
Каждый день — одна тема и четыре открытия: картина, статья, альбом и фильм. Рассматривайте, читайте, слушайте и ведите дневник.
```

**Description** (до 4000):

```
«Квартет» — маленький ежедневный выпуск о культуре. Каждый день одна тема и четыре открытия, которые её раскрывают: картина, статья, альбом и фильм. Без ленты, бесконечной прокрутки и рекламы — только то, на что стоит потратить время сегодня.

КАРТИНА
Медленный просмотр: подсказки по 20 секунд учат смотреть, а не пролистывать. Увеличение до мелких деталей, рассказ о том, что изображено и почему это важно.

СТАТЬЯ
Читалка прямо в приложении: чистая вёрстка, удобный шрифт, светлая, тёмная и сепия-тема. Статьи Википедии — без отвлекающих ссылок и сносок. Прочитанное сохраняется и открывается без интернета.

АЛЬБОМ
30-секундный фрагмент лучшего трека, чтобы понять настроение, и кнопка «Слушать» в вашем музыкальном сервисе.

ФИЛЬМ
О чём фильм и почему его стоит увидеть, трейлер и где посмотреть.

ДНЕВНИК ОТКРЫТИЙ
Отмечайте изученное, ставьте оценки и записывайте пару мыслей. Серия дней подряд, статистика по типам и экспорт дневника.

ВИДЖЕТЫ
«Квартет дня» с отметками прямо на экране «Домой», «Рекомендация дня» — картина, альбом, фильм или статья во весь виджет, и виджеты для экрана блокировки.

АРХИВ
Пропущенный день никуда не денется: все выпуски и отложенные рекомендации — в архиве.

Без регистрации, рекламы и слежки: всё, что вы отмечаете, хранится только на телефоне.
```

**Keywords** (до 100, через запятую без пробелов):

```
искусство,живопись,кино,музыка,альбомы,статьи,культура,музей,лонгриды,эрудиция,история,виджет
```

**Support URL** — обязательное поле: страница, где можно с вами связаться. Подойдёт та же страница,
что и для политики конфиденциальности (см. `docs/privacy-policy.md`), если в ней есть ваш e-mail.

**Marketing URL** — можно оставить пустым.

**Copyright:** `2026 <ваше имя>`

**Screenshots** — нужны для экрана **6,9″** (1320 × 2868 или 1290 × 2796) или **6,5″** (1284 × 2778 или
1242 × 2688), от 3 до 10 штук. Скриншоты из `docs/screenshots` уменьшены и не подойдут. Проще всего:
Xcode → выберите симулятор **iPhone 16 Pro Max** (или 17 Pro Max) → ▶︎ → в симуляторе **File → Save Screen**
(⌘S). Если ваш iPhone — Pro Max или Plus, подойдут и обычные скриншоты с телефона.

Порядок, который хорошо продаёт: выпуск дня → картина → медленный просмотр → читалка → дневник → виджеты.

## App Review Information

- **Sign-in required** — снимите галочку (аккаунтов нет).
- **Contact Information** — ваши имя, телефон и e-mail (их видит только Apple).
- **Notes** (по-английски, для проверяющего):

```
No account is needed. Every day the app shows a curated issue: one theme with a painting, an article, an album and a film, written by us and bundled in the app (catalog.json).
Images: paintings come from Wikimedia Commons (free licenses); album covers, 30-second previews and trailers come from the iTunes Search API with links to Apple Music / the iTunes Store.
Articles open in a reader view of the original public web page; the source is always named and "Open original" leads to the publisher's site.
Widgets: long-press the Home Screen → "+" → "Квартет". There are no purchases, ads, analytics or tracking; all user data stays on the device.
```

## App Privacy (левое меню → «Конфиденциальность приложения»)

- **Privacy Policy URL** — ссылка на опубликованный текст из `docs/privacy-policy.md`.
- **Data Collection** → «Нет, мы не собираем данные с этого приложения» (**Data Not Collected**).
  Это правда: аккаунтов, аналитики и рекламы нет, отметки и заметки хранятся только на телефоне.

## Возрастной рейтинг

Отвечайте честно на анкету. Само приложение не содержит ничего откровенного, но в описаниях фильмов,
трейлерах и статьях встречаются взрослые темы и насилие (например, «Фарго»). Разумно отметить
**«Редко/умеренно»** для «Реалистичное насилие» и «Темы для взрослых/провокационные темы» — получится
рейтинг около **12+/13+**. «Неограниченный доступ в интернет» — **нет**: приложение открывает только
статьи из своего каталога.

## Права на контент (Content Rights)

App Store Connect спросит, показывает ли приложение чужой контент и есть ли у вас права на него.
Ответ «да, контент сторонний» — честный. Перед ответом «права есть» стоит снизить риски:

- картины — свободные файлы Wikimedia Commons, это нормально;
- обложки, фрагменты и трейлеры из iTunes Search API Apple разрешает использовать вместе со ссылкой в свои сервисы;
- постеры и обложки, которых нет в iTunes, берутся из Википедии и часто **несвободны** — безопаснее
  отключить этот запасной вариант (`anyLicense` в `Shared/Media/MediaResolver.swift`, функция `findArtwork`);
- статьи открываются в режиме чтения оригинальной страницы с названием источника и ссылкой на неё.

## Цена и доступность

**Pricing and Availability** → цена **Free** (или своя), страны — все или выбранные. Для Евросоюза
App Store Connect спросит, являетесь ли вы торговцем (Digital Services Act): для бесплатного личного
проекта обычно отвечают «не торговец»; если выберете «торговец», ваши контакты будут показаны в карточке.

## Ответ на запрос App Review (Guideline 2.1 — Information Needed)

Вставьте в **App Review Information → Notes** (видео — в **Attachment** там же или ссылкой):

```
1. Screen recording: attached (recorded on iPhone, latest iOS). It starts with launching the app from the Home Screen and shows onboarding, today's issue, a painting (slow looking, zoom), an article in the reader, an album (30-second preview), a film (trailer), marking an item as done with a rating and note, the journal, the archive, settings, and the Home Screen widgets. The app has no accounts, no login, no user-generated content shared with others, and no paid content or in-app purchases.

2. Purpose and audience: Kvartet is a daily cultural digest for adults who want to learn about art, music, film and history in a few minutes a day. Every day it offers one theme and four curated recommendations that explore it: a painting, an article, an album and a film, each with a short explanation of what it is and why it matters. It replaces endless feeds with a small, finite daily issue and helps users keep a personal journal of what they have looked at, read, listened to and watched.

3. Setup: no login or setup is needed. Open the app, tap "Начать" (Start) on the welcome screen, and today's issue appears. Tap any card to open it: "Медленный просмотр" (slow looking) for paintings, "Читать" (read) for articles, the play button for album previews, "Трейлер" for films. Tap "Отметить как…" (Mark as done) at the bottom of an item to add it to the journal. Tabs: Today, Archive, Journal. Widgets: long-press the Home Screen → "+" → "Квартет".

4. External services: Wikipedia / Wikimedia Commons API (painting images, article texts), iTunes Search API by Apple (album covers, 30-second previews, film artwork and trailers, links to Apple Music / iTunes Store), and publishers' public web pages for articles (shown in a reader view with the source named and a link to the original). Links "Listen" / "Where to watch" open the music or video service the user chooses. No authentication, payment, analytics, advertising or AI services are used. The curated texts are written by us and bundled with the app.

5. Regions: the app works the same in all regions. The interface and content are in Russian. Availability of some iTunes previews and of the external music and video services depends on the user's country, as on any device.

6. Third-party material: paintings are public-domain or freely licensed files from Wikimedia Commons; Wikipedia texts are under CC BY-SA and attributed; covers, previews and trailers are provided by the iTunes Search API for promoting content in Apple's stores and link to it; articles are opened from their public pages with attribution and a link to the publisher. The app does not operate in a regulated industry.
```
