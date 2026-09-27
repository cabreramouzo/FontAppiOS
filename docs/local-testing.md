# Testing against the local backend

Debug builds talk to `http://127.0.0.1:8080` (`swift run App serve` in FontAppBE). Pass
`-FontAppAPI <url>` as a launch argument to point elsewhere. The local database is seeded:
nothing in it is a real figure, and nothing written here reaches production.

## Accounts (local database only)

| Username | Password | Role | Where it comes from |
|---|---|---|---|
| `prova_ios` | `Prova-yI1pmbJxaI` | user | Created with the app's native sign-up, 27/09/2026 |
| `marta_r`, `jordi88`, `laia_m`, … | `demo12345` | user | `swift run App seed --demo` (`SeedCommand.demoUsers`) |
| `xavi123` | `demo12345` | admin | Same seed; shows the staff purple |

These exist only in the local database. Never use them against production.

If `prova_ios` disappears (a re-seed with `--force`), create it again from the app
(My profile → Log in → No account yet? Sign up), or with:

```sh
curl -X POST http://127.0.0.1:8080/users -H 'Content-Type: application/json' \
  -d '{"name":"Prova iOS","username":"prova_ios","email":"prova.ios@example.com","password":"Prova-yI1pmbJxaI","lang":"es"}'
```

Sign-ups are limited to 5 an hour per IP (429), also locally.
