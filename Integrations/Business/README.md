# Business integration adapter

This adapter forwards Shop Manager, Kiosk, Furniture, and supply-order requests to `Config.Business.Resource` (default `m-business`).

It also synchronizes presentation configuration such as shop locations, catalog rows, VAT, and inventory mapping through `m-business:Configure`.

The adapter owns no business tables and exposes no public cross-resource API.
Authoritative signatures and result contracts are documented in
`m-business/API.md` in the separately distributed provider resource.
