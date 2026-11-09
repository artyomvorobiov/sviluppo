#!/usr/bin/env python3
"""Проверка каталога «Квартета» (Shared/Resources/catalog.json).

Запуск:  python3 scripts/validate_catalog.py [путь/к/catalog.json] [--online]

С флагом --online скрипт ещё и спрашивает Википедию: существуют ли статьи из поля wiki,
есть ли у картин свободное изображение и достаточно ли оно крупное (нужен интернет).

Ошибки (exit code 1): битый JSON, нет обязательных полей, повторяющиеся id,
неизвестные поля (часто это опечатка), неверные типы.
Предупреждения: необязательные, но желательные поля (подсказки к картине,
ключевой трек альбома и т. п.).
"""
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

DEFAULT_PATH = Path(__file__).resolve().parent.parent / "Shared" / "Resources" / "catalog.json"

KINDS = ["painting", "article", "album", "film"]
SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
WIKI = re.compile(r"^[a-z]{2,3}:\S.*$")

ITEM_FIELDS = {
    "id": str, "kind": str, "title": str, "originalTitle": str, "creator": str,
    "originalCreator": str, "year": str, "minutes": int, "details": list,
    "summary": str, "why": str, "lookFor": list, "fact": str, "more": list,
    "keyTrack": str, "url": str, "source": str, "wiki": str, "image": str, "search": str,
}
REQUIRED_ITEM = ["id", "kind", "title", "creator", "summary"]
ISSUE_FIELDS = {"id": str, "theme": str, "intro": str, "items": list}


USER_AGENT = "KvartetCatalogCheck/1.0 (https://github.com/artyomvorobiov/sviluppo)"
# Картина меньше этого по длинной стороне будет выглядеть мыльно на экране телефона.
MIN_PAINTING_PIXELS = 1500


def fetch_json(url: str) -> dict:
    """GET с паузами при ответе 429 (Википедия ограничивает частые запросы)."""
    for attempt in range(6):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            if exc.code != 429:
                raise
            time.sleep(15 * (attempt + 1))
    raise RuntimeError("Википедия отвечает «слишком много запросов» — попробуйте позже")


def check_online(items: list[dict], errors: list[str], warnings: list[str]) -> None:
    """Статьи из поля wiki существуют, у картин есть крупное свободное изображение; файлы из image доступны."""
    by_lang: dict[str, list[tuple[dict, str]]] = {}
    for item in items:
        if item.get("wiki") and WIKI.match(item["wiki"]):
            lang, title = item["wiki"].split(":", 1)
            by_lang.setdefault(lang, []).append((item, title.replace("_", " ")))
    for lang, entries in by_lang.items():
        for start in range(0, len(entries), 40):
            chunk = entries[start:start + 40]
            params = {
                "action": "query", "format": "json", "formatversion": "2", "redirects": "1",
                "prop": "pageimages", "piprop": "thumbnail|original", "pithumbsize": "2560",
                "pilicense": "free", "titles": "|".join(title for _, title in chunk),
            }
            query = fetch_json(f"https://{lang}.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params))["query"]
            renamed = {n["from"]: n["to"] for n in query.get("normalized", []) + query.get("redirects", [])}
            pages = {page["title"]: page for page in query.get("pages", [])}
            for item, title in chunk:
                while title in renamed:
                    title = renamed[title]
                page = pages.get(title)
                label = item["id"]
                if not page or page.get("missing"):
                    errors.append(f"{label}: статьи {item['wiki']} нет в Википедии")
                    continue
                if item["kind"] != "painting" or item.get("image"):
                    continue
                original = page.get("original") or {}
                if not page.get("thumbnail"):
                    errors.append(f"{label}: у статьи {item['wiki']} нет свободного изображения — укажите image")
                elif max(original.get("width", 0), original.get("height", 0)) < MIN_PAINTING_PIXELS:
                    warnings.append(
                        f"{label}: изображение всего {original.get('width')}×{original.get('height')} — "
                        "поищите файл крупнее на Commons и укажите его в image"
                    )
            time.sleep(2)

    files = {}
    for item in items:
        image = item.get("image", "")
        if "Special:FilePath/" in image:
            files[item["id"]] = urllib.parse.unquote(image.split("Special:FilePath/", 1)[1]).replace("_", " ")
    names = list(files.items())
    for start in range(0, len(names), 40):
        chunk = names[start:start + 40]
        params = {
            "action": "query", "format": "json", "formatversion": "2", "prop": "imageinfo",
            "iiprop": "size", "titles": "|".join(f"File:{name}" for _, name in chunk),
        }
        query = fetch_json("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params))["query"]
        renamed = {n["from"]: n["to"] for n in query.get("normalized", [])}
        pages = {page["title"]: page for page in query.get("pages", [])}
        for item_id, name in chunk:
            title = renamed.get(f"File:{name}", f"File:{name}")
            info = (pages.get(title, {}).get("imageinfo") or [{}])[0]
            if not info:
                errors.append(f"{item_id}: файла «{name}» нет на Wikimedia Commons")
            elif max(info.get("width", 0), info.get("height", 0)) < MIN_PAINTING_PIXELS:
                warnings.append(f"{item_id}: файл «{name}» всего {info.get('width')}×{info.get('height')}")
        time.sleep(2)


def main() -> int:
    args = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
    online = "--online" in sys.argv[1:]
    path = Path(args[0]) if args else DEFAULT_PATH
    errors: list[str] = []
    warnings: list[str] = []

    try:
        catalog = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        print(f"ОШИБКА: не удалось прочитать {path}: {exc}")
        return 1

    if catalog.get("schemaVersion") != 1:
        errors.append("schemaVersion должен быть равен 1")
    if "updated" in catalog and not re.match(r"^\d{4}-\d{2}-\d{2}$", str(catalog["updated"])):
        errors.append("updated должен быть в формате ГГГГ-ММ-ДД")
    issues = catalog.get("issues")
    if not isinstance(issues, list) or not issues:
        errors.append("issues должен быть непустым списком")
        issues = []

    issue_ids: Counter = Counter()
    item_ids: Counter = Counter()
    kinds_count: Counter = Counter()
    creators: Counter = Counter()

    for index, issue in enumerate(issues, start=1):
        where = f"выпуск {index}"
        if not isinstance(issue, dict):
            errors.append(f"{where}: должен быть объектом")
            continue
        for key in issue:
            if key not in ISSUE_FIELDS:
                errors.append(f"{where}: неизвестное поле «{key}»")
        for key, typ in ISSUE_FIELDS.items():
            value = issue.get(key)
            if not isinstance(value, typ) or (typ is str and not value.strip()) or (typ is list and not value):
                errors.append(f"{where}: поле «{key}» обязательно ({typ.__name__})")
        issue_id = issue.get("id", "")
        where = f"выпуск «{issue_id or index}»"
        issue_ids[issue_id] += 1
        if issue_id and not SLUG.match(issue_id):
            errors.append(f"{where}: id только из латиницы, цифр и дефисов")

        items = issue.get("items") or []
        issue_kinds = [item.get("kind") for item in items if isinstance(item, dict)]
        missing = [k for k in KINDS if k not in issue_kinds]
        if missing:
            warnings.append(f"{where}: нет рекомендаций типа {', '.join(missing)}")
        duplicates = [k for k, n in Counter(issue_kinds).items() if n > 1]
        if duplicates:
            errors.append(f"{where}: тип {', '.join(duplicates)} встречается больше одного раза")

        for item in items:
            if not isinstance(item, dict):
                errors.append(f"{where}: рекомендация должна быть объектом")
                continue
            item_id = item.get("id", "?")
            label = f"{where} / {item_id}"
            for key in item:
                if key not in ITEM_FIELDS:
                    errors.append(f"{label}: неизвестное поле «{key}»")
            for key, typ in ITEM_FIELDS.items():
                if key in item and not isinstance(item[key], typ):
                    errors.append(f"{label}: поле «{key}» должно быть {typ.__name__}")
            for key in REQUIRED_ITEM:
                if not item.get(key):
                    errors.append(f"{label}: нет обязательного поля «{key}»")
            item_ids[item_id] += 1
            if not SLUG.match(str(item_id)):
                errors.append(f"{label}: id только из латиницы, цифр и дефисов")

            kind = item.get("kind")
            if kind not in KINDS:
                errors.append(f"{label}: kind должен быть одним из {KINDS}")
                continue
            kinds_count[kind] += 1
            creators[(kind, item.get("creator"))] += 1

            for key in ("details", "lookFor", "more"):
                if key in item and not all(isinstance(x, str) and x.strip() for x in item[key]):
                    errors.append(f"{label}: «{key}» — список непустых строк")
            if "minutes" in item and item["minutes"] <= 0:
                errors.append(f"{label}: minutes должно быть больше нуля")
            if "wiki" in item and not WIKI.match(item["wiki"]):
                errors.append(f"{label}: wiki в формате «en:Название_статьи»")
            for key in ("url", "image"):
                if key in item and not item[key].startswith(("https://", "http://")):
                    errors.append(f"{label}: {key} должен начинаться с https://")

            if kind == "article" and not item.get("url"):
                errors.append(f"{label}: у статьи должен быть url")
            if kind == "album" and not item.get("keyTrack"):
                warnings.append(f"{label}: нет keyTrack — не будет 30-секундного фрагмента")
            if kind == "painting" and len(item.get("lookFor", [])) < 2:
                warnings.append(f"{label}: для «медленного просмотра» нужно хотя бы 2 подсказки lookFor")
            if kind == "painting" and not item.get("wiki") and not item.get("image"):
                warnings.append(f"{label}: у картины нет wiki/image — изображение не найдётся")
            if not item.get("minutes"):
                warnings.append(f"{label}: нет minutes")
            if len(item.get("summary", "")) > 700:
                warnings.append(f"{label}: summary длиннее 700 знаков")

    for issue_id, count in issue_ids.items():
        if count > 1:
            errors.append(f"id выпуска «{issue_id}» повторяется {count} раз(а)")
    for item_id, count in item_ids.items():
        if count > 1:
            errors.append(f"id рекомендации «{item_id}» повторяется {count} раз(а)")

    if online:
        all_items = [item for issue in issues if isinstance(issue, dict) for item in issue.get("items", []) if isinstance(item, dict)]
        try:
            check_online(all_items, errors, warnings)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"проверка в Википедии не удалась: {exc}")

    repeated = [f"{creator} ({kind}) ×{n}" for (kind, creator), n in creators.items() if n > 2 and kind != "article"]
    if repeated:
        warnings.append("часто повторяются авторы: " + "; ".join(repeated))

    for message in warnings:
        print(f"предупреждение: {message}")
    for message in errors:
        print(f"ОШИБКА: {message}")

    print(
        f"\nВыпусков: {len(issues)} · рекомендаций: {sum(kinds_count.values())} "
        f"(картин {kinds_count['painting']}, статей {kinds_count['article']}, "
        f"альбомов {kinds_count['album']}, фильмов {kinds_count['film']})"
    )
    if errors:
        print(f"Найдено ошибок: {len(errors)}")
        return 1
    print("Каталог в порядке ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
