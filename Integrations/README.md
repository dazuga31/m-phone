# Integration adapters

This folder contains thin adapters between device Apps and authoritative gameplay resources.

Current adapters:

- [Banking](Banking/README.md)
- [Business](Business/README.md)
- [Courier](Courier/README.md)
- [Jobs](Jobs/README.md)
- [Trucker](Trucker/README.md)

An adapter may normalize provider differences, but it must not duplicate the provider's persistence or business rules.

Provider selection belongs in `config.lua`. External resources should publish stable exports documented in their own root `API.md`.
