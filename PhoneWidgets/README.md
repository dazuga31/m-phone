# Phone Widgets

Phone Widgets provide glanceable data on the Phone home screen. They share the Widget SDK but declare `surfaces.phone = true`.

Built-in groups:

- [Clock](Clock/README.md)
- [Weather](Weather/README.md)
- [AppWidgets](AppWidgets/README.md)
- [CreatorLink](CreatorLink/README.md)

Every widget must support only the sizes it actually implements and return useful size-specific content.

Use [TemplateWidget](TemplateWidget/README.md) for custom widgets. Widget layout preferences are presentation state owned by `m-phone`; authoritative values remain in their gameplay resource.
