# Estates of Pinewood

This repository contains the source code for [estatesofpinewood.org](https://estatesofpinewood.org), a website for the Estates of Pinewood residential community in Altamonte Springs, FL.

The site is built with [Hugo](https://gohugo.io/), a fast static site generator. The source lives in the `hugo-site/` directory.

## Getting Started

### Install Hugo

On macOS using Homebrew:

```sh
brew install hugo
```

For other platforms, see the [Hugo installation docs](https://gohugo.io/installation/).

### Run the Development Server

```sh
cd hugo-site
hugo server
```

This starts a local server at `http://localhost:1313/` with live reload.

### Build for Production

```sh
cd hugo-site
hugo
```

The generated site is output to `hugo-site/public/`.

## Site Structure

```
hugo-site/
├── hugo.toml        # Site configuration
├── content/         # Page content (Markdown)
│   ├── _index.md    # Home page
│   ├── resources.md # Resources page
│   └── contact.md   # Contact page
├── layouts/         # HTML templates
│   ├── index.html   # Home page template
│   ├── _default/    # Default templates
│   └── partials/    # Reusable template fragments
├── static/          # Static assets (images, CSS, etc.)
└── archetypes/      # Content templates for `hugo new`
```
