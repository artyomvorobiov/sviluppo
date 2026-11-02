// Разбор статьи для читалки (Android). Повторяет parseScript из Kvartet/Reader/ReaderController.swift.
// Вызывается после Readability.js: kvartetParse(expectedTitle, plainText) → JSON-строка или null.
function kvartetParse(expectedTitle, plainText) {
  const result = (function () {
    if (typeof Readability === "undefined") { return null; }
    const documentClone = document.cloneNode(true);
    if (plainText) {
      // Сноски вида [1] и [прим. 2] без ссылок только мешают читать.
      documentClone.querySelectorAll("sup.reference, .mw-ref, .reference").forEach((node) => node.remove());
    }
    // Мобильная Википедия сворачивает разделы (hidden="until-found"), а Readability пропускает скрытое.
    documentClone.querySelectorAll('[hidden="until-found"]').forEach((node) => node.removeAttribute("hidden"));
    // Служебное у Википедии: «перенаправлено с…», ссылки «править», навигационные шаблоны.
    documentClone
      .querySelectorAll(".mw-redirectedfrom, #contentSub, #siteSub, .mw-editsection, .mw-jump-link, .navbox, .noprint")
      .forEach((node) => node.remove());
    const article = new Readability(documentClone, { charThreshold: 250 }).parse();
    if (!article || !article.content) { return null; }

    // Заголовок показывает сама читалка — убираем его повтор в начале текста.
    const normalize = (text) => (text || "").replace(/\u00AD/g, "").replace(/[^\p{L}\p{N}]+/gu, " ").trim().toLowerCase();
    const titles = [expectedTitle, article.title].map(normalize).filter((text) => text.length > 0);
    const parsed = new DOMParser().parseFromString(article.content, "text/html");
    const heading = parsed.body.querySelector("h1, h2, h3");
    if (heading) {
      const text = normalize(heading.textContent);
      const position = normalize(parsed.body.textContent).indexOf(text);
      if (text.length > 0 && titles.includes(text) && position >= 0 && position < 200) {
        heading.remove();
      }
    }

    if (plainText) {
      // Разделы со ссылками и источниками в конце статьи.
      const tail = ["примечания", "литература", "ссылки", "см также", "источники", "комментарии",
        "notes", "references", "external links", "see also", "further reading", "sources"];
      Array.from(parsed.body.querySelectorAll("h2, h3"))
        .filter((node) => tail.includes(normalize(node.textContent)))
        .forEach((node) => {
          let block = node;
          while (block.parentElement && block.parentElement !== parsed.body && block.parentElement.children.length === 1) {
            block = block.parentElement;
          }
          let next = block.nextElementSibling;
          while (next && !next.matches("h2, h3") && !next.querySelector("h2, h3")) {
            const current = next;
            next = next.nextElementSibling;
            current.remove();
          }
          block.remove();
        });
      // Ссылки превращаем в обычный текст, картинки внутри ссылок остаются.
      parsed.body.querySelectorAll("a").forEach((link) => link.replaceWith(...link.childNodes));
    }

    // Время чтения считаем по абзацам: сноски, таблицы и списки литературы почти никто не читает.
    const paragraphs = Array.from(parsed.body.querySelectorAll("p"))
      .reduce((sum, node) => sum + node.textContent.trim().length, 0);
    const total = article.length || 0;

    return {
      title: article.title || "",
      byline: article.byline || "",
      siteName: article.siteName || "",
      content: parsed.body.innerHTML,
      length: paragraphs > total * 0.3 ? paragraphs : total,
      lang: article.lang || document.documentElement.lang || ""
    };
  })();
  return result ? JSON.stringify(result) : null;
}
