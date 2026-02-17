# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Static website for the Estates of Pinewood residential community (Altamonte Springs, FL), built with Hugo. The Hugo source lives in `hugo-site/`. A legacy `hexo-site/` directory exists but is archived and not actively used.

## Commands

All commands must be run from the `hugo-site/` directory:

```sh
# Development server with live reload (http://localhost:1313/)
cd hugo-site && hugo server

# Production build (output to hugo-site/public/)
cd hugo-site && hugo

# Create a new content page
cd hugo-site && hugo new content/page-name.md
```

No package manager, build tools, or test framework is used — just Hugo.

## Architecture

**Hugo template hierarchy:**
- `layouts/_default/baseof.html` — base wrapper (head, header partial, content block, footer partial)
- `layouts/index.html` — home page (hero image, card grid)
- `layouts/_default/single.html` — generic fallback for content pages
- `layouts/_default/resources.html` and `contact.html` — page-specific layouts selected via `layout:` front matter in the corresponding content files
- `layouts/partials/header.html` and `footer.html` — shared navigation and footer

**Content model:** Three Markdown pages in `content/` (`_index.md`, `resources.md`, `contact.md`). Page-specific layouts are assigned via `layout` in front matter.

**Styling:** Single CSS file at `static/css/style.css` using CSS custom properties. Key design tokens: primary green `#2c6e49`, accent tan `#dda15e`. Fonts: Playfair Display (headings), Inter (body). Responsive breakpoint at 768px with hamburger mobile nav.

**Static assets:** Images in `static/img/`, downloadable PDFs in `static/docs/`.

**Site config:** `hugo-site/hugo.toml` defines base URL, site title, subtitle, contact email, and the main navigation menu.
