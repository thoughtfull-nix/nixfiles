let optionsData = null;
let tocData = null;
let currentFilters = {
  query: "",
  prefix: "",
};
let currentPage = 1;

const RESULTS_PER_PAGE = 25;
const DEBOUNCE_MS = 150;

async function init() {
  try {
    const [optionsResponse, tocResponse] = await Promise.all([
      fetch("options-data.json"),
      fetch("toc.json"),
    ]);

    optionsData = await optionsResponse.json();
    tocData = await tocResponse.json();

    console.log(`Loaded ${optionsData.length} options`);

    renderToc();
    performSearch();
    setupEventListeners();
  } catch (error) {
    console.error("Failed to initialize:", error);
    document.getElementById("results").innerHTML = `
      <div class="no-results">
        <h3>Failed to load options</h3>
        <p>${error.message}</p>
      </div>
    `;
  }
}

function renderToc() {
  const tocContainer = document.getElementById("toc");
  tocContainer.innerHTML = "";

  function renderNode(node, depth = 0, parentExpanded = false) {
    if (!node.name) {
      const wrapper = document.createElement("div");
      if (node.children) {
        node.children.forEach((child) => {
          wrapper.appendChild(renderNode(child, depth, true));
        });
      }
      return wrapper;
    }

    const nodeEl = document.createElement("div");
    nodeEl.className = `toc-node ${depth > 0 ? "nested" : ""}`;
    nodeEl.dataset.path = node.fullPath;

    const itemEl = document.createElement("div");
    itemEl.className = "toc-item";
    if (currentFilters.prefix === node.fullPath) {
      itemEl.classList.add("active");
    }

    const hasChildren = node.children && node.children.length > 0;

    // Check if this node should be expanded (if current prefix starts with this path)
    const shouldExpand =
      currentFilters.prefix &&
      (currentFilters.prefix === node.fullPath ||
        currentFilters.prefix.startsWith(node.fullPath + "."));

    if (hasChildren) {
      const toggleEl = document.createElement("span");
      toggleEl.className = `toc-toggle ${shouldExpand ? "expanded" : ""}`;
      toggleEl.textContent = "\u25B6";
      toggleEl.addEventListener("click", (e) => {
        e.stopPropagation();
        const childrenEl = nodeEl.querySelector(":scope > .toc-children");
        if (childrenEl) {
          toggleEl.classList.toggle("expanded");
          childrenEl.classList.toggle("expanded");
        }
      });
      itemEl.appendChild(toggleEl);
    } else {
      const spacer = document.createElement("span");
      spacer.style.width = "20px";
      spacer.style.display = "inline-block";
      itemEl.appendChild(spacer);
    }

    const nameEl = document.createElement("span");
    nameEl.textContent = node.name;
    itemEl.appendChild(nameEl);

    // Make entire row clickable for filtering
    itemEl.addEventListener("click", (e) => {
      e.stopPropagation();
      // Don't filter if clicking the toggle
      if (e.target.classList.contains("toc-toggle")) {
        return;
      }
      filterByPrefix(node.fullPath, nodeEl);
    });

    nodeEl.appendChild(itemEl);

    if (hasChildren) {
      const childrenEl = document.createElement("div");
      childrenEl.className = `toc-children ${shouldExpand ? "expanded" : ""}`;
      node.children.forEach((child) => {
        childrenEl.appendChild(renderNode(child, depth + 1));
      });
      nodeEl.appendChild(childrenEl);
    }

    return nodeEl;
  }

  tocContainer.appendChild(renderNode(tocData));
}

function filterByPrefix(prefix, clickedNode) {
  // Remove active class from previous selection
  const prevActive = document.querySelector(".toc-item.active");
  if (prevActive) {
    prevActive.classList.remove("active");
  }

  // Add active class to clicked item
  if (clickedNode) {
    const itemEl = clickedNode.querySelector(":scope > .toc-item");
    if (itemEl) {
      itemEl.classList.add("active");
    }

    // Expand this node if it has children
    const toggleEl = clickedNode.querySelector(":scope > .toc-item > .toc-toggle");
    const childrenEl = clickedNode.querySelector(":scope > .toc-children");
    if (toggleEl && childrenEl) {
      toggleEl.classList.add("expanded");
      childrenEl.classList.add("expanded");
    }
  }

  currentFilters.prefix = prefix;
  currentFilters.query = "";
  currentPage = 1;

  const searchInput = document.getElementById("search-input");
  searchInput.value = "";

  performSearch();
}

function setupEventListeners() {
  const searchInput = document.getElementById("search-input");

  let debounceTimer;
  searchInput.addEventListener("input", (e) => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      currentFilters.query = e.target.value;
      currentFilters.prefix = ""; // Clear prefix filter when searching
      currentPage = 1;
      // Clear active state in TOC
      const prevActive = document.querySelector(".toc-item.active");
      if (prevActive) {
        prevActive.classList.remove("active");
      }
      performSearch();
    }, DEBOUNCE_MS);
  });
}

function performSearch() {
  const resultsContainer = document.getElementById("results");
  const resultsInfo = document.getElementById("results-info");

  let results;

  if (currentFilters.query) {
    // Split query into terms and require ALL terms to match (in name or description)
    const terms = currentFilters.query.toLowerCase().split(/\s+/).filter(Boolean);

    results = optionsData.filter((opt) => {
      const searchText = (opt.name + " " + (opt.descriptionPlain || "")).toLowerCase();
      return terms.every((term) => searchText.includes(term));
    });
  } else if (currentFilters.prefix) {
    // Filter by prefix (exact prefix match)
    const prefix = currentFilters.prefix + ".";
    results = optionsData.filter(
      (opt) => opt.name === currentFilters.prefix || opt.name.startsWith(prefix)
    );
  } else {
    results = [...optionsData];
  }

  results.sort((a, b) => a.name.localeCompare(b.name));

  const totalCount = results.length;
  const totalPages = Math.ceil(totalCount / RESULTS_PER_PAGE);
  const startIndex = (currentPage - 1) * RESULTS_PER_PAGE;
  const endIndex = startIndex + RESULTS_PER_PAGE;
  const displayResults = results.slice(startIndex, endIndex);

  const startNum = totalCount === 0 ? 0 : startIndex + 1;
  const endNum = Math.min(endIndex, totalCount);

  if (totalCount === 0) {
    resultsInfo.innerHTML = `<span>No options found</span>`;
  } else if (totalCount === 1) {
    resultsInfo.innerHTML = `<span>1 option found</span>`;
  } else {
    const lastName = displayResults[displayResults.length - 1]?.name || "";
    resultsInfo.innerHTML = `
      <span>Showing ${startNum}-${endNum} of ${totalCount.toLocaleString()} options</span>
      <span class="results-info-last">${escapeHtml(lastName)}</span>
    `;
  }

  if (displayResults.length === 0) {
    resultsContainer.innerHTML = `
      <div class="no-results">
        <h3>No options found</h3>
        <p>Try adjusting your search or filter</p>
      </div>
    `;
    document.getElementById("pagination-top").innerHTML = "";
    document.getElementById("pagination-bottom").innerHTML = "";
    return;
  }

  resultsContainer.innerHTML = displayResults.map((opt) => renderOptionCard(opt)).join("");
  renderPagination(totalPages);
}

function renderPagination(totalPages) {
  const paginationTop = document.getElementById("pagination-top");
  const paginationBottom = document.getElementById("pagination-bottom");

  if (totalPages <= 1) {
    paginationTop.innerHTML = "";
    paginationBottom.innerHTML = "";
    return;
  }

  const pages = [];
  const maxVisible = 9;

  if (totalPages <= maxVisible) {
    for (let i = 1; i <= totalPages; i++) {
      pages.push(i);
    }
  } else {
    pages.push(1);

    if (currentPage > 4) {
      pages.push("...");
    }

    const start = Math.max(2, currentPage - 2);
    const end = Math.min(totalPages - 1, currentPage + 2);

    for (let i = start; i <= end; i++) {
      if (!pages.includes(i)) {
        pages.push(i);
      }
    }

    if (currentPage < totalPages - 3) {
      pages.push("...");
    }

    if (!pages.includes(totalPages)) {
      pages.push(totalPages);
    }
  }

  let html = "";

  // Previous button
  html += `<button class="page-btn" ${currentPage === 1 ? "disabled" : ""} data-page="${currentPage - 1}">&laquo;</button>`;

  // Page numbers
  for (const page of pages) {
    if (page === "...") {
      html += `<span class="page-ellipsis">...</span>`;
    } else {
      html += `<button class="page-btn ${page === currentPage ? "active" : ""}" data-page="${page}">${page}</button>`;
    }
  }

  // Next button
  html += `<button class="page-btn" ${currentPage === totalPages ? "disabled" : ""} data-page="${currentPage + 1}">&raquo;</button>`;

  paginationTop.innerHTML = html;
  paginationBottom.innerHTML = html;

  // Add event listeners to both
  [paginationTop, paginationBottom].forEach((container) => {
    container.querySelectorAll(".page-btn").forEach((btn) => {
      btn.addEventListener("click", () => {
        const page = parseInt(btn.dataset.page, 10);
        if (!isNaN(page) && page >= 1 && page <= totalPages) {
          currentPage = page;
          performSearch();
          // Scroll so pagination is fully visible at top
          const paginationTop = document.getElementById("pagination-top");
          const headerHeight = document.querySelector(".header").offsetHeight;
          const targetY = paginationTop.getBoundingClientRect().top + window.scrollY - headerHeight - 16;
          window.scrollTo({ top: targetY, behavior: "smooth" });
        }
      });
    });
  });
}

function renderOptionCard(option) {
  const badges = [];
  if (option.readOnly) {
    badges.push('<span class="badge readonly">read-only</span>');
  }

  const sources = option.declarations
    .filter((d) => d.url && d.source !== "unknown")
    .map((d) => {
      const pathParts = d.url.split("/blob/main/");
      const shortPath = pathParts.length > 1 ? pathParts[1] : d.url.split("/").slice(-2).join("/");
      return `<a href="${escapeHtml(d.url)}" class="source-link" target="_blank" rel="noopener">
        ${escapeHtml(shortPath)}
      </a>`;
    })
    .join("");

  const details = [];

  if (option.default) {
    details.push(`
      <div class="option-detail">
        <span class="option-detail-label">Default</span>
        <div class="option-detail-value">
          <pre>${escapeHtml(option.default)}</pre>
        </div>
      </div>
    `);
  }

  if (option.example) {
    details.push(`
      <div class="option-detail">
        <span class="option-detail-label">Example</span>
        <div class="option-detail-value">
          <pre>${escapeHtml(option.example)}</pre>
        </div>
      </div>
    `);
  }

  return `
    <article class="option-card" id="${escapeHtml(option.id)}">
      <header class="option-header">
        <h2 class="option-name">${escapeHtml(option.name)}</h2>
        <div class="option-badges">${badges.join("")}</div>
      </header>
      <div class="option-type">Type: ${escapeHtml(option.type)}</div>
      ${option.description ? `<div class="option-description">${renderMarkdown(option.description)}</div>` : ""}
      ${details.length > 0 ? `<div class="option-details">${details.join("")}</div>` : ""}
      ${sources ? `<div class="option-sources">${sources}</div>` : ""}
    </article>
  `;
}

function escapeHtml(str) {
  if (!str) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function renderMarkdown(text) {
  if (!text) return "";
  return marked.parse(text);
}

init();
