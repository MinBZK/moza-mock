# moza-mock

Mocks voor externe API's en MOZa-services, als standalone WireMock.

## Structuur

- `mappings/` - de stubs: request-matching en responsemetadata (status, headers). Eén stub per bestand, of meerdere stubs per service in een `"mappings": [...]` array.
- `__files/` - de responsebodies waar de mappings naar verwijzen via `bodyFileName`, per service een submap.
- `bruno/` - Bruno-collectie (`mocks`) met een request per stub. Openen via *Open Collection* en de map `bruno/` kiezen (niet importeren), daarna environment `lokaal` selecteren. Elk request assert de verwachte statuscode, dus de hele collectie draaien werkt ook als smoketest.

## Mock toevoegen of aanpassen

1. Zet de responsebody in de servicemap onder `__files/`, bijvoorbeeld `__files/mijnservice/endpoint-response.json`.
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
    "bodyFileName": "mijnservice/endpoint-response.json"
  }
}
```

Voor bestaande mocks: matching aanpassen doe je in de mapping (`url`, `urlPattern` voor regex, `method`), de body staat in `__files/`.

## Wat wordt gemockt

Externe API's:

- Ondernemersplein: `dop-articles.json`, `dop-subsidies.json`
- KVK Handelsregister: `handelsregister.json`
- SRU officiële publicaties: `repo-overheid.sru.json`
- NotifyNL (voor de NMC): `notifynl.json`, zie [NotifyNL](#notifynl)

MOZa-services:

- NMC: `nmc.json`
- Profielservice: `profielservice.json`
- Verificatieservice: `verificatieservice.json`
- Actualiteitenservice: `actualiteitenservice.json`
- CloudEvents-ontvanger (`POST /events`): `notificatie-events.json`

De testdata gebruikt overal dezelfde partij: "Test BV Donald", KVK 68750110, donald@testbv.nl. Dat sluit aan op de handelsregister-mock.

`profielservice.json` bevat naast de echte API (`POST /partij` enz.) ook de stubs uit [moza-poc-fbs-berichtenbox](https://github.com/MinBZK/moza-poc-fbs-berichtenbox). Die PoC bevraagt de profielservice via `GET /api/profielservice/v1/{identificatieType}/{identificatieNummer}` en leest scopes als OIN-identificatie. Let op: geen `dienst`-object met UUID in die scope-responses zetten, de PoC leest `dienst.id` als getal.

### NotifyNL

`notifynl.json` speelt NotifyNL voor de NMC: `POST /v2/notifications/email`, `GET /v2/notifications/{id}` (de navraag) en `GET /v2/notifications?reference=` (de herclaim na een verlopen lease). De mock controleert de JWT niet; de NMC heeft wel een `NOTIFY_API_KEY` van minstens 74 tekens zonder spaties nodig om op te starten, de inhoud doet er verder niet toe.

De mock gebruikt de `reference` uit het verzoek (bij de NMC het poging-id) als NotifyNL-id. Zo horen het antwoord op de POST, de receipt en de navraag bij elkaar zonder dat de mock iets hoeft te onthouden. Een POST zonder `reference`, of met een `reference` die geen UUID in kleine letters is, krijgt een 400.

**Receipts.** Na een geslaagde POST stuurt de mock de delivery receipt zelf naar de NMC, als webhook: na 1 s een `sending`, na 4 s de eindstatus. Waarheen, bepaalt het eerste padsegment van de NotifyNL-url die de NMC gebruikt:

| `QUARKUS_REST_CLIENT_NOTIFY_URL` van de NMC | Receipt gaat naar |
|---|---|
| `https://<mock>/notifynl/stable` (of zonder prefix: `https://<mock>`) | `https://nmcapi-stable-nd-j7s.rig.prd1.gn2.quattro.rijksapps.nl/api/nmc/v1/notifynl-callback` |
| `https://<mock>/notifynl/pr-76` | `https://nmcapi-pr-76-nd-j7s.rig.prd1.gn2.quattro.rijksapps.nl/api/nmc/v1/notifynl-callback`, en zo voor elke ZAD-deployment |
| `http://localhost:8090/notifynl/lokaal` | `http://host.containers.internal:8080/api/nmc/v1/notifynl-callback`, of de waarde van de omgevingsvariabele `WIREMOCK_NOTIFYNL_LOKAAL_URL` van de mock: een NMC op de host naast een mock in een container. De NMC luistert in dev-mode zelf op 8080, publiceer de mock dan op een andere hostpoort (`podman run -p 8090:8080 ...`), anders komt de receipt bij de mock zelf terecht |
| `.../notifynl/zelf` | de mock zelf (`nmc.json` heeft een stub voor `POST /api/nmc/v1/notifynl-callback`); de receipts zijn dan terug te zien via `POST /__admin/requests/find` |

De receipt draagt `Authorization: Bearer <token>`; het token komt uit de omgevingsvariabele `WIREMOCK_NOTIFYNL_CALLBACK_TOKEN` van de mock en heeft geen standaardwaarde, zodat er geen waarde in deze publieke repository staat. Zet op de NMC-deployment dezelfde waarde in `NOTIFY_CALLBACK_BEARER_TOKEN`. Ontbreekt het token bij de mock of verschillen de waarden, dan weigert de NMC de receipt met 401. Het antwoord van de NMC op een receipt staat in `GET /__admin/requests`, bij het POST-verzoek aan de mock onder `subEvents` (type `WEBHOOK_RESPONSE`); in het log van de mock staat het niet. Lokaal kun je elke waarde kiezen, bijvoorbeeld `podman run -e WIREMOCK_NOTIFYNL_CALLBACK_TOKEN=lokaal-token ...`.

Het token is leesbaar voor iedereen die de mock kan bereiken: `GET /__admin/requests` toont bij elke verstuurde receipt de `Authorization`-header, en met target `zelf` staat het ook in het request op de eigen callback-stub. Daarnaast stuurt de mock een receipt met het juiste token naar elke `nmcapi-<target>`-deployment, voor iedereen die een POST doet op `/notifynl/<target>/v2/notifications/email`. Gebruik daarom een waarde die alleen geldt voor NMC-deployments die aan de mock gekoppeld zijn, en nooit het token van een deployment die met de echte NotifyNL praat. Hetzelfde journal toont elk verzoek van de NMC aan de mock, met het e-mailadres van de ontvanger en de `personalisation`, tot de mock herstart. Gebruik op een NMC-deployment die aan de mock gekoppeld is daarom alleen testadressen.

**Scenario's** kies je met een deel van het e-mailadres van de ontvanger (ook als `+`-tag, zoals `donald+permanent-failure@testbv.nl`); zie de tabel bij [Foutscenario's](#foutscenarios). Zonder herkenbaar deel: 201 en een receipt `delivered`. De navraag en het zoeken op reference staan los van het adres: de navraag geeft `delivered` voor elk id, behalve de ids met de prefix uit de `geen-receipt-*`-scenario's; het zoeken op reference vindt altijd één verzending met status `sending`.

Let op bij de navraag: de NMC doet die pas 1 uur na de verzending (`nmc.navraag.momenten`). Voor een snelle testronde zet je die momenten op de NMC-deployment korter, bijvoorbeeld `NMC_NAVRAAG_MOMENTEN=1m,2m,3m`.

De map `notifynl` in de Bruno-collectie controleert de mock zelf, met een request voor elk scenario uit de tabel behalve `traag`. De requests gebruiken target `zelf`; de requests 13 en 22 wachten elk 5 s en controleren dan in het journal welke receipts zijn aangekomen. Draai de map vanuit `bruno/` met `bru run notifynl --env lokaal`. Het journal staat in het geheugen van de mock: blijft de mock draaien, dan tellen de receipts van een eerdere run mee.

## Foutscenario's

Standaard krijg je het happy path. Met deze waarden (als `identificatieNummer`, als padsegment bij het GET-contract, of bij NotifyNL als deel van het e-mailadres of als id-prefix) krijg je een andere respons:

| Waarde | Waar | Respons |
|---|---|---|
| `999996915` | profielservice partij-lookup (GET en POST) | 404 |
| `999996915` | NMC `POST /centraal/notificaties` | 400 |
| `999991401` | profielservice partij-lookup (GET en POST) | 500 |
| `111222333` | profielservice partij-lookup (GET en POST) | 200, partij zonder voorkeuren |
| `verificatieCode: "000000"` | `POST /emailverificatie` | 400 |
| `code: "000000"` | verificatieservice `POST /verify` | 200 met `success: false` |
| `999992222` | profielservice partij-lookup (POST), `POST /contactgegeven`, `POST /voorkeur` | de soft-delete-partij: bevat alleen de opnieuw toegevoegde rijen |
| `5017de1e-0001-4000-8000-000000000001` | `DELETE`/`PUT /contactgegeven` | 404, contactgegeven heeft al een soft delete |
| `5017de1e-0003-4000-8000-000000000003` | `DELETE`/`PUT /voorkeur` | 404, voorkeur heeft al een soft delete |
| `email: "verwijderd@testbv.nl"` | `POST /emailverificatie` | 400 |
| `email: "verwijderd@testbv.nl"` | `POST /emailverificatie/code` | 404 |
| `999992223` | profielservice `POST /contactgegeven`, `POST /voorkeur` | 409, contactgegeven/voorkeur bestaat al |
| e-mailadres bevat `permanent-failure`, `temporary-failure` of `technical-failure` | NotifyNL `POST /v2/notifications/email` | 201, receipt met die eindstatus |
| e-mailadres bevat `geen-receipt` | NotifyNL `POST /v2/notifications/email` | 201, geen receipt; navraag op het id geeft `delivered` |
| e-mailadres bevat `geen-receipt-mislukt` | NotifyNL `POST /v2/notifications/email` | 201, id met prefix `ffffffff-`; navraag geeft `permanent-failure` |
| e-mailadres bevat `geen-receipt-onbekend` | NotifyNL `POST /v2/notifications/email` | 201, id met prefix `40440440-`; navraag geeft 404 |
| e-mailadres bevat `geen-receipt-sending` | NotifyNL `POST /v2/notifications/email` | 201, id met prefix `5e4d1400-`; navraag blijft `sending` |
| e-mailadres bevat `afgewezen` | NotifyNL `POST /v2/notifications/email` | 400 `ValidationError` op `email_address` (adresafwijzing voor de NMC) |
| e-mailadres bevat `buiten-team` | NotifyNL `POST /v2/notifications/email` | 400 `BadRequestError` (ontvanger niet op de guest list van een team-key) |
| e-mailadres bevat `te-druk` | NotifyNL `POST /v2/notifications/email` | 429 `RateLimitError` |
| e-mailadres bevat `storing` | NotifyNL `POST /v2/notifications/email` | 500 |
| e-mailadres bevat `traag` | NotifyNL `POST /v2/notifications/email` | 201 na 35 s, voorbij de read-timeout van 30 s van de NMC |
| id met prefix `40440440-` | NotifyNL `GET /v2/notifications/{id}` | 404 |

Deze stubs hebben een expliciete `priority` zodat ze winnen van de generieke stub voor dezelfde URL (lager getal wint, default is 5).

### Soft delete in de profielservice

Verwijderen in de profielservice is een soft delete: de rij blijft bestaan met een
`verwijderd_op`-tijdstempel, maar verdwijnt uit alle leespaden. Wat dat betekent voor de mock
en de collectie:

- `DELETE /contactgegeven/{id}` en `DELETE /voorkeur/{id}` hebben **geen request body** meer en
  geven 204. Een tweede DELETE op dezelfde id geeft 404: de rij is niet meer vindbaar.
- `PUT /contactgegeven` en `PUT /voorkeur` geven **204** in plaats van 200, en 404 op een id
  met een soft delete.
- Dezelfde waarde opnieuw toevoegen na een verwijdering herstelt de oude rij niet, maar levert
  een **nieuwe rij met een nieuwe id** op (201). De unieke indexen zijn partieel
  (`WHERE verwijderd_op IS NULL`), dus de verwijderde rij bezet de sleutel niet meer.
- Een e-mailadres met een soft delete is niet meer te verifieren en krijgt geen nieuwe
  verificatiecode.
- Was het verwijderde contactgegeven of de verwijderde voorkeur de laatste actieve rij van de
  partij, dan wordt de partij zelf ook soft-deleted: `POST /partij` geeft daarna **404**. Het
  `e2e-contactgegeven`-scenario laat dit zien (e2e-stap 8, na het verwijderen van het enige
  contactgegeven van die partij).
- Een contactgegeven of voorkeur toevoegen is geen upsert meer: bestaat de combinatie
  (partij, type, waarde) resp. (partij, voorkeurType, scope) al actief, dan geeft
  `POST /contactgegeven` of `POST /voorkeur` nu **409** in plaats van 200.

De stubs hiervoor zijn stateless: ze hangen aan de vaste ids en waarden uit de tabel hierboven,
niet aan een WireMock-scenario. De stateful variant (aanmaken, bijwerken, verwijderen) staat in
het `e2e-contactgegeven`-scenario.

## Bruno-environments

De collectie heeft per service een url-variabele, met vier environments:

- `lokaal`, `sp`, `zad`: alle variabelen wijzen naar de mock (respectievelijk localhost, het SP-cluster en ZAD).
- `Dev omgeving`: elke variabele wijst naar de echte service, behalve `notifynlUrl`: die ontbreekt daar, want de echte NotifyNL vraagt een JWT op basis van de API-key en de map `notifynl` is alleen bedoeld om de mock te controleren. Let op: POST/PUT/DELETE doen dan echte mutaties, de foutscenario-waarden bestaan daar niet, en de verificatieservice is alleen in-cluster bereikbaar. De KVK-testomgeving vereist een `apikey`-header; de publieke testkey staat in het environment.

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
