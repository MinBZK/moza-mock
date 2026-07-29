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

## Bruno-environments

De collectie heeft per service een url-variabele, met vier environments:

- `lokaal`, `sp`, `zad`: alle variabelen wijzen naar de mock (respectievelijk localhost, het SP-cluster en ZAD).
- `Dev omgeving`: elke variabele wijst naar de echte service. Let op: POST/PUT/DELETE doen dan echte mutaties, de foutscenario-waarden bestaan daar niet, en de verificatieservice is alleen in-cluster bereikbaar. De KVK-testomgeving vereist een `apikey`-header; de publieke testkey staat in het environment.

De create-requests zetten het id uit de response in een variabele (`contactgegevenId`, `voorkeurId`, `referenceId`, de voorkeur-ids uit `4-voorkeuren`); de bijbehorende update- en delete-requests gebruiken die variabele. Zo ruimt een create gevolgd door een delete zichzelf op, ook tegen de echte services. In de mock-environments staan defaults voor die id-variabelen (de fixture-ids van de mock), zodat een delete of update ook los uitgevoerd kan worden; in `Dev omgeving` staan die bewust niet.

De map `e2e` is een end-to-end test over de echte services heen: contactgegeven aanmaken in de profielservice, notificatie versturen via de NMC, e-mailadres bijwerken, opnieuw versturen, en opruimen. Draai de map als geheel (rechtermuisklik, *Run*) tegen het `Dev omgeving`-environment, of met `bru run e2e --env "Dev omgeving"`. Tegen de mock-environments slaagt de flow ook: voor BSN 999993653 heeft de mock een stateful WireMock-scenario (aangemaakt, bijgewerkt, verwijderd) met de standaard donald-adressen; een nieuwe create begint de cyclus opnieuw. De scenario-state staat in het geheugen van de mock en kan gereset worden met `POST /__admin/scenarios/reset`. Let op bij `Dev omgeving`: `e2eEmail` en `e2eEmailNieuw` moeten in NotifyNL gewhitelist zijn, anders geeft de NMC een 500 op het versturen.

## Lokaal draaien

```powershell
podman run --rm -p 8080:8080 `
  -v "${PWD}\mappings:/home/wiremock/mappings" `
  -v "${PWD}\__files:/home/wiremock/__files" `
  wiremock/wiremock:3.13.2
```

Handig bij het debuggen: `/__admin/mappings` toont de geladen stubs, `/__admin/requests/unmatched` de requests die geen stub raakten (met closest match).
