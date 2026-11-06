<p align="center">
  <img src="docs/assets/banner.png" alt="JB Kaizen for Claude Code" width="100%">
</p>

<h1 align="center">JB Kaizen для Claude Code</h1>

<p align="center"><b>Нічна джоба, яка читає, що ви з Claude реально робили сьогодні, і переписує ваші скіли та агентів так, щоб завтра було менше токенів, менше повторів і менше вашої уваги.</b></p>

<p align="center"><a href="README.md">English README</a></p>

---

Поведінка Claude Code живе у файлах, які належать вам: `~/.claude/skills/*/SKILL.md`, `~/.claude/agents/*.md`,
`CLAUDE.md`, memory проєктів. Вони стають кращими лише тоді, коли ви сідаєте й редагуєте їх - тобто ніколи.
**JB Kaizen** перетворює цю рутину на цикл:

1. **Щоночі** запланований `claude -p` прокидається і читає *нові* докази з минулого разу - git-коміти, коментарі
   з PR-рев'ю, транскрипти сесій, memory проєктів. Уже опрацьовану історію він ніколи не перечитує.
2. **Шукає** в них те, що механічно зламалося (tool calls, які впали і були мовчки обійдені), що ви виправляли,
   що рев'юери відмічають раз за разом, і який скіл ви *мали на увазі*, а Claude вибрав інший.
3. **Мультиагентний propose → adversarial verify** перетворює знахідки на мінімальні правки з посиланням на докази.
   Кожна правка потребує більшості 2-з-3 верифікаторів; усе, що міняє якість на швидкість, відкидається.
4. Кожна правка **знімається в снапшот, версіонується і застосовується**, а журнал пояснює що і чому змінилося.
   Відкат - одна команда.

Через місяць ефект видно: рев'юер перестає пропускати той самий клас багів, роутинг-хук з першого разу відправляє
«подивись в логах чому впало» в правильний скіл, токенів на задачу менше, і ранок іде на роботу, а не на
повторне пояснення того самого.

А ще він працює [у парі з Hoply](#у-парі-з-hoply): о 17:15 Claude Code пропонує переглянути й підтвердити ваш день.

> Витягнуто з приватного сетапу, де цей цикл крутився **66 епох поспіль** (червень - вересень 2026) по ~70
> репозиторіях. Усе проєктно-специфічне прибрано, усі вистраждані правила двигуна лишилися.

## Як це працює

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/diagrams/how-it-works.uk.dark.svg">
  <img alt="Як це працює: докази йдуть у двигун self-learn, який змінює скіли, агентів, роутинг-мапу і журнал" src="docs/assets/diagrams/how-it-works.uk.light.svg" width="1000">
</picture>

### Ніч від початку до кінця

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/diagrams/nightly-run.uk.dark.svg">
  <img alt="Нічний запуск від початку до кінця" src="docs/assets/diagrams/nightly-run.uk.light.svg" width="1000">
</picture>

### Чому це безпечно лишати без нагляду

- **Двофазні курсори.** `paginate` тільки пропонує батч у `pending/`; курсор рухається лише після успішного
  аналізу. Падіння посеред ночі = той самий батч перечитується, нічого не пропускається.
- **Снапшот перед правкою.** `snapshots/<id>/<version>/` - джерело істини для відкату:
  `/self-learn rollback <id> <version>`.
- **Deny-list на рівні permissions**, не лише в промпті: `~/Documents`, `~/.ssh`, `rm -rf`, force-push.
- **Стеля бюджету** `--max-budget-usd` (єдина, що працює при агентному fan-out) + жорстка стеля 45 агентів,
  вшита лічильником у скрипт, + 4 години на спробу з убивством усієї process group.
- **Propose за замовчуванням.** Інтерактивно нічого не редагується без `apply`; вночі все «гейтоване»
  (реструктуризації, правки багатьох скілів, непідтверджені архівації) іде в журнал на вашу наступну сесію.

### Цикл feedback → скіл

Memory проєкту - найдорожчий вхід: `MEMORY.md` вантажиться в *кожну* сесію. Kaizen трактує кожну feedback-нотатку
як баг-репорт проти скіла: або скіл вивчає правило (мінімальна правка), або доводить, що вже його знає. В обох
випадках нотатка йде в архів з однорядковим вказівником, і `MEMORY.md` худне.

## Встановлення

Потрібно: [Claude Code](https://code.claude.com/docs/en/setup) (`claude` у `PATH`), `git`, `jq`, `python3`.
Опційно: `gh` (авторизований) для PR-рев'ю, `npx ccusage` для фази балансу моделей.

### Одним рядком

```bash
npx -y jb-kaizen                                                   # Node 18+
brew install moriarty33/tap/jb-kaizen && jb-kaizen                 # Homebrew
curl -fsSL https://raw.githubusercontent.com/Moriarty33/jb-kaizen/main/bootstrap.sh | bash
```

Усі три запускають той самий інсталятор, і він питає лише дві речі:

1. **Поставити рекомендований набір? [Y/n]** - Y додає плагін Claude Code з усіма скілами, нічне навчання о 03:07,
   хук роутингу, аліаси `/kz-*` і нагадування Hoply в робочі дні. n: введіть потрібні скіли через кому
   (`hoply-day, commit`) - і отримаєте саме їх, як персональні скіли.
2. **Ваш токен Hoply** (введення приховане, Enter пропускає) - див. [У парі з Hoply](#у-парі-з-hoply).

Решта бере дефолти; змінити їх можна потім через `/kaizen:setup` або `./install.sh --wizard`. Для скриптів:
`jb-kaizen --yes` (рекомендований набір без Hoply), `jb-kaizen --hoply` (лише підключити Hoply), `jb-kaizen --help`.

### Усередині Claude Code (плагін)

```
/plugin marketplace add Moriarty33/jb-kaizen
/plugin install kaizen@jb-kaizen
/kaizen:setup
```

Скіли стають `/kaizen:self-learn`, `/kaizen:model-balance`, `/kaizen:loop-audit`, `/kaizen:hoply-day`,
[вбудовані скіли](#вбудовані-скіли) і `/kaizen:setup`; хуки приходять разом із плагіном - без правок
`settings.json`. `/kaizen:setup` ставить сім питань майстра плюс Hoply і додає чотири короткі аліаси:

| Скорочено | Плагін | Клонування / bootstrap |
|-----------|--------|------------------------|
| `/kz-setup` | `/kaizen:setup` | термінальний майстер (`./install.sh --wizard`) |
| `/kz-learn` | `/kaizen:self-learn` | `/self-learn` |
| `/kz-audit` | `/kaizen:loop-audit` | `/loop-audit` |
| `/kz-balance` | `/kaizen:model-balance` | `/model-balance` |

Не потрібні - `--no-aliases` або скажіть це `/kaizen:setup`; вибір запам'ятовується в `config.json`.

### Клонування

```bash
git clone https://github.com/Moriarty33/jb-kaizen.git
cd jb-kaizen
./install.sh                                  # майстер налаштування: сім питань, Enter лишає дефолт
```

| Крок | Питає | Навіщо |
|------|-------|--------|
| 1 Залежності | поставити те, чого бракує (`gh`, `node`, `uv`, `graphify`, `code`...) | обов'язкові лише `git`, `jq`, `python3` |
| 2 Корені | де лежать ваші git-репозиторії | одна або кілька тек; нові репо під ними підхоплюються самі |
| 3 Репозиторії | які зі знайдених вивчати | будь-який можна вимкнути; у проєкти нічого не пишеться |
| 4 Хук роутингу | ставити підказку `UserPromptSubmit` | один рядок, коли збігається вивчена фраза; інакше тиша |
| 5 Нічний запуск | запускати щоночі і о котрій | launchd / systemd --user / рядок для crontab |
| 6 Приватний remote | бекапити сховище | там назви і шляхи проєктів: лише приватні репозиторії |
| 7 VS Code | `claude-launcher`, `graphify-watch` | див. [Компаньйони для редактора](#компаньйони-для-редактора) |

Відповіді зберігаються в `~/.claude/self-learn/config.json`, тож оновлення та інші машини проходять тихо
(поза терміналом майстер не питає нічого). Прапорці пропускають питання і запам'ятовуються: `--workspace DIRS`,
`--schedule [HH:MM]`, `--store-remote URL`, `--hook/--no-hook`, `--vscode LIST`, `--aliases/--no-aliases`,
`--skills LIST`, `--hoply-reminder/--no-hoply-reminder`, `--plugin`, `--yes`.

Спершу спробуйте інтерактивно: `/self-learn status` (епоха, що відстежується), `/self-learn` (повний прохід, лише
пропозиції з поясненнями), потім `/self-learn apply` (снапшот + застосування).

`./install.sh --help` - усі прапорці; `./uninstall.sh` прибирає все (сховище лишається, якщо не `--purge-store`;
`--hoply` ще й відключає Hoply). Плагінне встановлення: спершу зніміть заплановані джоби -
`ROOT="$(ls -td "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/kaizen/*/ | head -1)"; bash "$ROOT/uninstall.sh"`,
потім `/plugin uninstall kaizen@jb-kaizen`.

## У парі з Hoply

<a href="https://hoply.work"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/hoply-logo.dark.svg">
  <img alt="Hoply" src="docs/assets/hoply-logo.light.svg" height="40">
</picture></a>

[Hoply](https://hoply.work) тримає ваш час в одному місці - записи Harvest, зустрічі Google, робочі сесії GitHub,
посилання на Jira - і пропонує те, чого бракує. У парі з JB Kaizen він закриває день за вас:

- **О 17:15 за Києвом у робочі дні** Claude Code один раз пропонує переглянути день (хук, тихий і офлайн до
  того часу), а коли сесії немає - те саме каже сповіщення на робочому столі. Обидва замовкають, щойно день закрито.
- **`/kaizen:hoply-day`** показує, що вже записано, що ще не синхронізовано, і відкриті пропозиції; ви
  підтверджуєте, правите або відхиляєте їх, і нічого не записується, поки ви не скажете «так» точному списку.
- **Підключення:** у Hoply відкрийте Connectors - Claude Code, скопіюйте токен і вставте, коли інсталятор
  спитає (або пізніше: `npx -y jb-kaizen --hoply`). Hoply додається як віддалений MCP-сервер (`claude mcp get hoply`).
- **Приватність:** токен лежить у `~/.config/hoply/token` (0600) і доходить до Claude Code лише через скрипт
  `headersHelper`, ніколи не через `~/.claude.json`. Hoply не бачить нічого з ваших сесій; формулювання робить
  Claude локально, а текст із Hoply (назви зустрічей, нотатки) - це дані, ніколи не інструкції.

## Вбудовані скіли

Чотири щоденні скіли йдуть разом із плагіном, без прив'язки до проєкту; налаштовуються необов'язковим
`.claude/dev.config.json` (шукається від поточної теки вгору: `workspaceRoot`, `repos`, `githubOrg`, `baseBranch`,
`branchPrefix`, `ticketPattern`, `commit.*`, `commands.<repo>.lintFix|typecheck`):

| Скіл | Що робить |
|------|-----------|
| `/kaizen:commit` | коміт із префіксом тікета з ваших змін, спершу лінт, ніколи `--no-verify` |
| `/kaizen:review-code` | суворе самостійне рев'ю гілки P0-P4, спершу мапа архітектури, правки лише після вашого «так» |
| `/kaizen:fix-pr-comments` | відповідає на кожен відкритий тред рев'ю: виправити, пропустити з причиною чи позначити застарілим |
| `/kaizen:github` | правила git/gh, яких тримаються інші три: `git -C`, ощадливий `gh`, безпечні мержі |

При клонуванні вони звуться `/commit`, `/review-code`... і ніколи не перезаписують ваш скіл з такою самою назвою.

## Що і куди ставиться

| Шлях | Що |
|------|----|
| `~/.claude/plugins/cache/<marketplace>/kaizen/<version>/` | **плагінне встановлення**: скіли, `hooks/hooks.json`, `install.sh`, `uninstall.sh` - замість рядків `~/.claude/skills/*` нижче. `lib/skill-dir.sh` резолвить найновішу закешовану версію за mtime теки, а не за номером версії, тож старий залишок після `/plugin update` ніколи не переможе |
| `~/.claude/skills/self-learn/` | шлях клонування/bootstrap: двигун - `SKILL.md`, 14 bash-скриптів, довідники (workflow, роутинг-рубрика, learned patterns) |
| `~/.claude/skills/model-balance/` | шлях клонування/bootstrap: аудит моделі × зусилля з даних `ccusage` (фаза 2.8, опційно) |
| `~/.claude/skills/loop-audit/` | шлях клонування/bootstrap: контракт із 6 частин + три запобіжники для будь-якого автономного циклу |
| `~/.claude/skills/kz-{setup,learn,audit,balance}/` | обидва шляхи: короткі аліаси, по одному `SKILL.md`, що ведуть до `setup` / `self-learn` / `loop-audit` / `model-balance`; `--no-aliases` їх не ставить |
| `~/.claude/hooks/skill-router.py` | шлях клонування/bootstrap: хук `UserPromptSubmit`, один рядок підказки, коли збігається вивчена фраза; інакше тиша - плагін приносить цей хук сам, див. рядок вище |
| `~/.claude/skills/{hoply-day,commit,review-code,fix-pr-comments,github}/` | шлях клонування/bootstrap: перегляд дня Hoply і [вбудовані скіли](#вбудовані-скіли); ваш скіл з такою самою назвою лишається |
| `~/.claude/hooks/hoply-day-nudge.py` | шлях клонування/bootstrap: хук `SessionStart` + `UserPromptSubmit`, що раз на робочий день з 17:15 за Києвом пропонує переглянути день - плагін приносить його в `hooks/hooks.json` |
| `~/.config/hoply/token`, `headers.sh` | токен Hoply (0600) і `headersHelper`, що його надсилає; `uninstall.sh --hoply` прибирає обидва |
| `~/Library/LaunchAgents/com.self-learn.hoply-day.plist` | сповіщення в робочі дні (Linux: `self-learn-hoply-day.timer`); `--no-hoply-reminder` прибирає його |
| `~/.claude/lib/claude-retry.sh` | обмежені ретраї, бюджет часу, kill усієї process group, стоп на auth-помилці |
| `~/.claude/lib/skill-dir.sh` | резолвить теку скіла на диску для обох варіантів - клонування/bootstrap і плагіна; підключається нічним раннером і скриптами скілів |
| `~/.claude/night-guard-settings.json` | deny-list для нічного запуску |
| `~/.claude/self-learn/` | **приватне сховище**: курсори, реєстр, версії, снапшоти, роутинг-мапа, журнал, нічна джоба |
| `~/.claude/self-learn/config.json` | ваші відповіді майстру: корені, вимкнені репо, хук, розклад, remote, вибір VS Code, аліаси |
| `~/.vscode/extensions/local.claude-launcher-*` | опційно: кнопка-ракета, що відкриває `claude` у корені вікна |
| `~/.vscode/extensions/local.graphify-watch-*` | опційно: тримає graphify-граф відкритої теки актуальним |

## Компаньйони для редактора

У `vscode/` лежать два невеликі розширення VS Code (MIT, сирці плюс зібраний `.vsix`; ставляться через CLI `code`
кроком 7 майстра або `vscode/install-vscode.sh`). Обидва опційні, двигун від них не залежить.

- **claude-launcher** додає кнопку-ракету в заголовок редактора. Один клік відкриває термінал у корені вікна
  (тека або директорія з `.code-workspace`) і запускає `claude --permission-mode auto`. Кожен проєкт на один клік
  від сесії, тож більше вашої роботи потрапляє у транскрипти, з яких вчиться двигун.
- **graphify-watch** тримає актуальним граф знань [graphify](https://pypi.org/project/graphifyy/) відкритої теки:
  нативний file watching VS Code, дебаунс і одноразовий `graphify update` на зміни коду, стан у status bar,
  захист від усадки графа з одним автоматичним `--force`, і lock, щоб два вікна не перебудовували одночасно.
  З актуальним графом агенти відповідають «як X пов'язано з Y» зі звуженого підграфа, а не grep-ом по дереву.
  Потребує `graphify`; крок 1 майстра ставить його через `uv tool install graphifyy` і додає скіл `/graphify`.

**Нові проєкти** не потребують налаштування: кожен запуск пересканує корені,
`scripts/register.sh <path>` з резолвленої теки скіла (див. `lib/skill-dir.sh`) реєструє репо одразу
після `git init`, а `./install.sh --wizard` вимикає будь-який.

## Як виглядає одна ніч

Справжній журнал (назви проєктів прибрано), епоха 66 приватної лінії:

> **8 правок застосовано.** 0 із 33 вердиктів проголосували «keep» як запропоновано - усі 33 дали *correction*,
> тож кожен відвантажений рядок - це звужений текст верифікатора. Два класи ЗАКРИТО з цифрами і без правок.
>
> **Покриття:** 92 нових коміти / 9 репо · 47 PR / 416 коментарів / 173 людських · 1 312 транскриптів ·
> 217 файлів memory · 38 агентів / 1,37M токенів / 0 помилок / 527 с при стелі 45.
>
> **Закрито з цифрами:** «користувач постійно просить коротший вивід» - 129 збігів regex, ~123 з них - текст
> скілів, відлунений у user-записи; справжніх запитів ≈ 6 у 4 сесіях. Це не правило.

Останній абзац і є суть: двигун витрачає стільки ж зусиль на *спростування* власних знахідок, скільки на їх пошук.

## Конфігурація

| Де | Що |
|----|----|
| `registry.json` | `repos[key].enabled`, `repos[key].config.{batch,maxTotal,botLogins}`, глобальний `botLogins` |
| `nightly-prompt.txt` | контракт запуску: скоуп, фази, бюджет |
| `scripts/nightly-run.sh` | `SELF_LEARN_MODEL`, `SELF_LEARN_BUDGET_USD`, `CLAUDE_RETRY_TIMEOUT`, `SELF_LEARN_WORKSPACE` |
| `routing/routing-map.json` | вивчені фрази для хука (будь-якою мовою, разом із помилками диктування) |

## Автор

**Богдан Ямінський** - engineering manager, будує агентні workflow, які самі себе окуповують.
GitHub [@Moriarty33](https://github.com/Moriarty33) · LinkedIn [bogdan-jaminski](https://www.linkedin.com/in/bogdan-jaminski/)

MIT © 2026 Bogdan Jaminski
