#!/usr/bin/env python3
"""Проверка каталога «Квартета» (Shared/Resources/catalog.json).

Запуск:  python3 scripts/validate_catalog.py [путь/к/catalog.json]

Ошибки (exit code 1): битый JSON, нет обязательных полей, повторяющиеся id,
неизвестные поля (часто это опечатка), неверные типы.
Предупреждения: необязательные, но желательные поля (подсказки к картине,
ключевой трек альбома и т. п.).
"""
import json
import re
import sys
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


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PATH
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

    repeated = [f"{creator} ({kind}) ×{n}" for (kind, creator), n in creators.items() if n > 2]
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
