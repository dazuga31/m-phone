# Weather widget

The Weather widget reads synchronized weather and time through the current `qb-weathersync` callback and renders size-specific Phone content.

If the provider is unavailable, the client returns a controlled `ClearSkies`/midday fallback so the home screen remains functional.

The widget is presentation only. Weather ownership and synchronization remain in the configured weather resource. A future provider adapter should preserve the current widget payload shape.
