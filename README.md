# moza-mock

Mocks voor externe API's en MOZa-services, als standalone WireMock.

## Structuur

- `mappings/` - de stubs: request-matching en responsemetadata (status, headers). Eén stub per bestand, of meerdere stubs per service in een `"mappings": [...]` array.
- `__files/` - de responsebodies waar de mappings naar verwijzen via `bodyFileName`.
- `bruno/` - Bruno-collectie (`mocks`) met een request per stub. Openen via *Open Collection* en de map `bruno/` kiezen (niet importeren), daarna environment `lokaal` selecteren. Elk request assert de verwachte statuscode, dus de hele collectie draaien werkt ook als smoketest.

## Mock toevoegen of aanpassen

1. Zet de responsebody in `__files/`, bijvoorbeeld `mijn-endpoint-response.json`.
2. Maak een mapping in `mappings/`:

```json
{
  "request": {
    "method": "GET",
    "url": "/api/v1/mijn-endpoint"
  },
  "response": {
    "status": 200,
    "headers": {
      "Content-Type": "application/json"
    },
    "bodyFileName": "mijn-endpoint-response.json"
  }
}
```

Voor bestaande mocks: matching aanpassen doe je in de mapping (`url`, `urlPattern` voor regex, `method`), de body staat in `__files/`.

## Wat wordt gemockt

Externe API's:

- Ondernemersplein: `dop-articles.json`, `dop-subsidies.json`
- KVK Handelsregister: `handelsregister.json`
- SRU officiële publicaties: `repo-overheid.sru.json`

MOZa-services:

- NMC: `nmc.json`
- Profielservice: `profielservice.json`
- Verificatieservice: `verificatieservice.json`
- Actualiteitenservice: `actualiteitenservice.json`
- CloudEvents-ontvanger (`POST /events`): `notificatie-events.json`

De testdata gebruikt overal dezelfde partij: "Test BV Donald", KVK 68750110, donald@testbv.nl. Dat sluit aan op de handelsregister-mock.

`profielservice.json` bevat naast de echte API (`POST /partij` enz.) ook de stubs uit [moza-poc-fbs-berichtenbox](https://github.com/MinBZK/moza-poc-fbs-berichtenbox). Die PoC bevraagt de profielservice via `GET /api/profielservice/v1/{identificatieType}/{identificatieNummer}` en leest scopes als OIN-identificatie. Let op: geen `dienst`-object met UUID in die scope-responses zetten, de PoC leest `dienst.id` als getal.

## Foutscenario's

Standaard krijg je het happy path. Met deze waarden (als `identificatieNummer`, of als padsegment bij het GET-contract) krijg je een andere respons:

| Waarde | Waar | Respons |
|---|---|---|
| `999996915` | profielservice partij-lookup (GET en POST) | 404 |
| `999996915` | NMC `POST /centraal/notificaties` | 400 |
| `999991401` | profielservice partij-lookup (GET en POST) | 500 |
| `111222333` | profielservice partij-lookup (GET en POST) | 200, partij zonder voorkeuren |
| `verificatieCode: "000000"` | `POST /emailverificatie` | 400 |
| `code: "000000"` | verificatieservice `POST /verify` | 200 met `success: false` |

Deze stubs hebben een expliciete `priority` zodat ze winnen van de generieke stub voor dezelfde URL (lager getal wint, default is 5).

## Lokaal draaien

```powershell
podman run --rm -p 8080:8080 `
  -v "${PWD}\mappings:/home/wiremock/mappings" `
  -v "${PWD}\__files:/home/wiremock/__files" `
  wiremock/wiremock:3.13.2
```

Handig bij het debuggen: `/__admin/mappings` toont de geladen stubs, `/__admin/requests/unmatched` de requests die geen stub raakten (met closest match).
