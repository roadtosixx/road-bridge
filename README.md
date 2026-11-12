# Bridge

The existing `Bridge.*` API supports ESX, QBCore, Qbox and standalone setups. The Bridge is the editable integration layer; application code continues to call its API directly.

## Loading

The manifest executes three entry points:

- `bridge/init.lua`: initializes the framework and imports shared helpers, callbacks, events, locales and voice normalization.
- `bridge/client.lua`: imports the client modules after configuration and locales.
- `bridge/server.lua`: imports the server modules after configuration and the MySQL adapter.

These files use a private `require` instance. Each module runs once per resource runtime. Existing modules populate the global `Bridge` table, preserving the application API. To add a module, put its literal import in the appropriate entry point:

```lua
local require = Bridge.Require
require('bridge.modules.player.server')
```

Only plaintext, escrow-exempt Bridge files should call this loader. Both callers and imported modules must remain in `escrow_ignore`. Shared and client import sources must also appear in the manifest's `files` list so `LoadResourceFile` can read them on clients. Server sources are deliberately absent from that list.

The loader has its own `package`, `runtime`, `require`, `loadfile`, `dofile` and JSON helper. It preserves the global ox_lib loader and cache while sharing application globals, including `Bridge`, `Config`, `ESX`, `QBCore`, `Locales` and `_U`.

## Callbacks

Keep using the existing signatures:

```lua
-- Server: register from a thread, and answer every branch.
CreateThread(function()
    Bridge.RegisterCallback('roadphone:example', function(source, cb, value)
        cb(value)
    end)
end)

-- Client
Bridge.TriggerCallback('roadphone:example', function(value)
    -- Consume the response.
end, 'example')
```

Responses are delivered once. Synchronous handler errors are logged and answer with `nil`. ESX and QBCore retain their framework timeout policy. Qbox keeps its existing ten-second server deadline. Standalone requests answer with `nil` after ten seconds, use one resource-scoped response event, and discard duplicate, expired and previous-session replies. Arguments and replies preserve `nil` positions.

Callbacks remain responsible for authorization, validation and preventing repeated transactions. A callback timeout does not cancel work already running on the server.

`Bridge.NUI.Send` copies its payload before setting `event`. `Bridge.NUI.Proxy` preserves `false` results and returns `{ ok = false, error = 'no_response' }` only for `nil` results.

## Bundled loader

`vendor/require.lua` comes from [overextended/cfxlua-require](https://github.com/overextended/cfxlua-require/tree/0961b740f7f4d01346cf64340709696db50a005c), commit `0961b740f7f4d01346cf64340709696db50a005c`, under MPL-2.0. The full license is in `vendor/LICENSE`. No separate `require` resource is needed.

Local changes replace Cfx-specific syntax with standard Lua syntax and clear the loading sentinel if a searcher or compilation fails. Missing files, syntax errors and runtime errors can therefore be retried without a false circular-dependency error. Actual circular imports still fail with diagnostics.

Run `npm test` and `npm run lint`. Module coverage follows literal imports, verifies client availability and escrow exemptions, and checks that server Bridge sources stay out of the client packfile. Lua integration tests execute both entry points and verify caching and callback behavior. An encrypted customer build still needs an in-game smoke test.
