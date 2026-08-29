# Tablet Apps

Tablet Apps use the shared App SDK but must declare `surfaces.tablet = true` and provide a layout designed for the wider Tablet frame.

Phone support is not inherited. Do not enable `surfaces.phone` until the same App has a tested narrow layout.

Use [TemplateApp](TemplateApp/README.md) as the copy-ready starting point. Tablet App state, installation, ordering, and drag/drop layout remain separate from Phone state.
