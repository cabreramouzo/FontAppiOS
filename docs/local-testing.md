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

## Where the simulator is

The simulator starts in Cupertino, where the ICGC and IGN layers have no data and there
are no fountains: the map looks empty (it says so now, with a button to the world map).
Running from Xcode, the shared scheme `FontApp` simulates Moià instead
(`FontApp/Simulator/Moia.gpx`, Run → Options → Default Location). Launched any other way
(the simulator tools, `simctl launch`), set it by hand:

```sh
xcrun simctl location booted set 41.8108,2.0967
```

## On a real iPhone

A Debug build asks `127.0.0.1`, which on a phone is the phone itself: signing in fails
with "No connection to the server" and the login stays on screen. The login sheet shows
the server it uses (Debug builds only) for that reason. To test on a phone:

1. Start the backend on the network, not only on loopback:
   `swift run App serve --hostname 0.0.0.0` (in FontAppBE).
2. In Xcode, Edit Scheme → Run → Arguments, add `-FontAppAPI http://<Mac's LAN IP>:8080`
   (System Settings → Wi-Fi → Details shows the IP). Phone and Mac on the same Wi-Fi.
3. iOS asks for local network access the first time; allow it.

Don't point a Debug build at production to test writes: reviews and photos would be real.
