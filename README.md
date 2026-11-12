# Dockwell catalog

The apps [Dockwell](https://github.com/Dockwell/dockwell) offers to install. Every Dockwell install reads this repository as its catalog source `dockwell`, following `main`: an entry merged here reaches each install within about an hour, as a change on its Activity that it can undo. Nothing installed changes until a person plans an upgrade.

## What's here

- `entries/<id>.yaml`: one entry for each app, in a file named by its ID.
- `entries/media/`: the logos and screenshots the entries name, with where each came from: `manifest.json`, `NOTICE.txt` and `licenses/`.

## Writing an entry

An entry is YAML in the fields of [`dockwell.catalog.v1alpha1.Entry`](https://github.com/Dockwell/dockwell/blob/main/proto/dockwell/catalog/v1alpha1/entry.proto). The entries here are its examples.

- `id`, `name`, `summary`, `category` and `version` say what the app is. `release` starts at 1 and goes up with every change to the entry.
- `license` is the entry's own, `AGPL-3.0-only`, and `appLicense` the app's. `source` names this repository and the entry's file.
- `compose` is a Compose file. Each image is pinned by its digest, as `image@sha256:<digest>`.
- `inputs` are what a person gives, or Dockwell generates, used in the Compose file as `${NAME}`.
- `icon`, and each screenshot's `path`, name an image in `entries/media/` as `media/<file>`: WebP, PNG or JPEG, 1 MiB at most, never SVG. Record where it came from in `manifest.json`, and keep its notice in `licenses/`.

The format is set out in Dockwell's [ADR 0029](https://github.com/Dockwell/dockwell/blob/main/docs/adr/0029-a-catalog-format-fed-from-other-catalogs.md), and this repository in [ADR 0077](https://github.com/Dockwell/dockwell/blob/main/docs/adr/0077-dockwells-catalog-in-its-own-repository.md).

## Checking an entry

CI runs the check a Dockwell server makes when it reads this repository, so what merges is what installs show. To run it yourself, with Go:

```sh
git clone https://github.com/Dockwell/dockwell
cd dockwell
go run ./cmd/dockwell-catalog check ../catalog/entries
```

It names each file a server would leave out, and why. `.github/dockwell-commit` is the commit of Dockwell that CI checks with.

## Licence

The entries are AGPL-3.0-only, as Dockwell is: see [LICENSE](LICENSE). The images are the apps' own, and keep their own terms: see [entries/media/NOTICE.txt](entries/media/NOTICE.txt).
