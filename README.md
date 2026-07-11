# 👰🤵 Digital Bordsplacering & Gästportal för Bröllop

Ett skräddarsytt multiplattformsverktyg utvecklat i **Flutter** för att underlätta bröllopsplanering. Applikationen automatiserar bordsplacering baserat på sociala relationer och fungerar som en interaktiv gästportal på bröllopsdagen.

---

## 🚀 Arkitektur & Teknisk Stack

- **Frontend:** Flutter (Kompileras till både Web och Mobil)
  - *Webbvy:* Optimerad för brudparets administrationspanel (storskärm med Drag-and-Drop).
  - *Mobilvy:* Responsiv och strömlinjeformad vy för gästernas RSVP, schema och interaktiva bordskarta.
- **Backend/Databas:** Serverless-arkitektur med molndatabas (t.ex. Supabase, Firebase Firestore eller Cloudflare D1). För bildlagring krävs en Storage-hink (t.ex. Supabase Storage eller Firebase Storage).
- **Automatisering:** Cron-jobb / Cloudflare Workers Triggers för schemalagda uppgifter.
- **E-post:** Resend eller SendGrid API för automatiska utskick.

---

## 💡 Huvudfunktioner

### 1. Bordsplacering & Algoritm (Admin-vy)
- **Flexibla bordsformer:** Skapa och konfigurera bord i olika former (kvadrat, rektangel, cirkel, oval) med valfritt antal sittplatser.
- **Visuell Canvas & Drag-and-Drop:** Förhandsgranska placeringen visuellt och finjustera manuellt genom att dra och släppa gäster.
- **Anpassningsbara algoritmregler (Kryssrutor):** Brudparet kan inför körning slå av/på exakt vilka regler algoritmen ska ta hänsyn till:
  - **Sitt med bekant:** Krav på att alla ska känna minst en person vid sitt bord.
  - **Partners ihop:** Krav på att partners ska sitta precis bredvid varandra.
  - **Titelbaserad placering:** Regler för var gäster med specifika roller (t.ex. Best Man, tärna, föräldrar) ska placeras i förhållande till brudparet (Samma bord / Närliggande bord / Spelar ingen roll).
- **Gästtitlar & Roller:** Möjlighet att tilldela roller till gäster (t.ex. *Maid of Honor*, *Best Man*, *Förälder*, *Syskon*, *Barn*).
- **Undvik ("Nemesis"):** Sätt strikta regler för vilka personer som *inte* får sitta vid samma bord.
- **Låsta platser:** Lås specifika gäster på fasta stolar innan algoritmen körs.
- **Visuell validering:** Borden varnar (t.ex. lyser rött) om ett bord blir överfullt eller om aktiverade relationsregler bryts under manuell flytt.

### 2. RSVP & Gästportal (Gäst-vy)
- **Lösenordsfri RSVP:** Gäster söker på sitt namn via en unik länk (`wedding_id`) för att tacka ja eller nej.
- **Frivilligt telefonnummer:** Gästen kan valfritt ange sitt telefonnummer vid registrering (eller så läggs det in av admin) för smidigare kontakt.
- **Kost & Allergier:** Gäster fyller i specialkost direkt vid RSVP, vilket uppdaterar administrationspanelen direkt.
- **Sökbar Bordskarta:** På bröllopsdagen kan gäster söka på sitt namn i mobilen varpå deras tilldelade bord och stol lyser upp och zoomas in.

### 3. Landningssida & Info
- **Digital Inbjudan:** Välkomstsida med bild, datum och nedräkning. Brudparet kan ladda upp sin egen bild, annars visas en generisk standardbild.
- **Kartintegration:** Universella djuplänkar till Google Maps och Apple Maps för både vigselplats och festlokal.
- **Dagens Schema:** En interaktiv tidslinje med hålltider för hela dagen.

### 4. Automatisering & Utskick
- **RSVP-Deadline:** Gäster som inte svarat i tid stryks automatiskt och exkluderas från algoritmen och kockarnas matlistor.
- **Admin Override:** Administratörer kan när som helst återuppliva en struken gäst manuellt och tilldela plats/matval.
- **Automatiska Påminnelser:** 
  - *Till gästerna:* Mailas ut automatiskt en vecka innan deadline till de som inte svarat.
  - *Till brudparet:* Ett sammanfattande mail med lista på alla som inte svarat, komplett med namn och telefonnummer för enkel telefonjakt.

---

## 💾 Databasstruktur & Relationer

Här är en relationell databasmodell (anpassad för t.ex. PostgreSQL/Supabase eller SQLite/D1) som stöder flera bröllop i samma system.

┌──────────────┐             ┌──────────────┐
│   weddings   │1         0..│    guests    │
│──────────────│────────────►│──────────────│
│ id (PK)      │             │ id (PK)      │
└──────────────┘             │ wedding_id(FK)
└──────────────┘
│ 1      │ 1
│        │
▼ 0..   ▼ 0..*
┌──────────────────────────┐
│     guest_relations      │
│──────────────────────────│
│ guest_id_1 (PK, FK)      │
│ guest_id_2 (PK, FK)      │
└──────────────────────────┘

### 1. Tabell: `weddings`
Lagrar information om själva bröllopet och agerar toppnivå i datamodellen.

| Kolumnnamn | Datatyp | Restriktioner | Beskrivning |
| :--- | :--- | :--- | :--- |
| `id` | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() | Unikt ID för bröllopet. |
| `slug` | VARCHAR(255) | UNIQUE, NOT NULL | Används i URL:en (t.ex. `anna-och-erik`). |
| `date` | TIMESTAMP | NOT NULL | Datum och tid för bröllopet. |
| `rsvp_deadline` | TIMESTAMP | NOT NULL | Sista datumet för gäster att svara. |
| `cover_image_url` | TEXT | | URL till brudparets uppladdade omslagsbild (valfri). |
| `venue_name` | VARCHAR(255) | NOT NULL | Namn på festlokalen/restaurangen. |
| `venue_address`| TEXT | NOT NULL | Adress till festlokalen (för kartlänkar). |
| `church_name` | VARCHAR(255) | | Namn på kyrkan/vigselplatsen (valfri). |
| `church_address`| TEXT | | Adress till vigselplatsen (valfri). |
| `rule_must_know_someone` | BOOLEAN | DEFAULT TRUE | Algoritmregel: Måste känna någon vid bordet. |
| `rule_partners_together` | BOOLEAN | DEFAULT TRUE | Algoritmregel: Partners måste sitta ihop. |
| `rule_titles_placement`  | VARCHAR(50) | DEFAULT 'SameTable' | Titelplacering: `SameTable`, `NearbyTable`, `Anywhere`. |
| `created_at` | TIMESTAMP | DEFAULT NOW() | Skapelsedatum för posten. |

### 2. Tabell: `guests`
Innehåller alla bjudna gäster och deras aktuella status.

| Kolumnnamn | Datatyp | Restriktioner | Beskrivning |
| :--- | :--- | :--- | :--- |
| `id` | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() | Unikt ID för gästen. |
| `wedding_id` | UUID | FOREIGN KEY REFERENCES `weddings(id)` ON DELETE CASCADE | Koppling till specifikt bröllop. |
| `first_name` | VARCHAR(100) | NOT NULL | Gästens förnamn. |
| `last_name` | VARCHAR(100) | NOT NULL | Gästens efternamn. |
| `email` | VARCHAR(255) | | E-postadress för påminnelser (valfri). |
| `phone_number` | VARCHAR(50) | | Telefonnummer för manuell uppföljning (valfri). |
| `title_role` | VARCHAR(50) | | Roll/Titel: `MaidOfHonor`, `BestMan`, `Parent`, `Sibling`, `Child` (valfri). |
| `rsvp_status` | VARCHAR(50) | DEFAULT 'Pending' | Status: `Pending`, `Attending`, `Declined`, `Overdue`. |
| `dietary_restrictions` | TEXT | | Allergier och specialkost. |
| `table_id` | VARCHAR(100) | | ID eller nummer på tilldelat bord. |
| `seat_number` | INTEGER | | Specifikt stolnummer vid bordet. |
| `is_locked` | BOOLEAN | DEFAULT FALSE | Om gästen är fastlåst vid sin plats. |

### 3. Tabell: `guest_relations`
En kopplingstabell (Many-to-Many) som definierar hur gästerna känner eller förhåller sig till varandra inom samma bröllop.

| Kolumnnamn | Datatyp | Restriktioner | Beskrivning |
| :--- | :--- | :--- | :--- |
| `guest_id_1` | UUID | PRIMARY KEY, FOREIGN KEY REFERENCES `guests(id)` ON DELETE CASCADE | Första gästen i relationen. |
| `guest_id_2` | UUID | PRIMARY KEY, FOREIGN KEY REFERENCES `guests(id)` ON DELETE CASCADE | Andra gästen i relationen. |
| `relation_type`| VARCHAR(50) | NOT NULL | Typ av relation: `Partner`, `Friend`, `Avoid`. |

---

## 👥 User Stories (Användarberättelser)

> ⚠️ **VIKTIGT:** När en del eller ett acceptanskriterium är helt färdigutvecklat och testat **SKA DEN BOCKAS I** i listan nedan (`- [ ]` ändras till `- [x]`).

Denna backlog är uppdelad utifrån de två primära rollerna i systemet: **Brudpar (Administratörer)** och **Bröllopsgäster**.

### 🏗️ Brudpar / Admin (Webbgränssnitt)

#### 1. Hantera Bordskonfiguration
> **Som ett** brudpar,  
> **vill jag** kunna lägga till bord med olika former och platser på en digital rumsyta,  
> **så att** jag kan spegla festlokalens faktiska layout.
- [ ] **Kan välja form:** Möjlighet att välja mellan formerna kvadrat, rektangel, cirkel och oval för varje bord.
- [ ] **Dynamiska platser:** Möjlighet att ändra antalet stolar upp till maxgränsen individuellt per bord.
- [ ] **Fri canvas:** Kunna flytta runt borden fritt på en visuell canvas via drag-and-drop.

#### 2. Hantera Gästlista, Telefonnummer & Titlar
> **Som ett** brudpar,  
> **vill jag** kunna lägga till gäster med kontaktuppgifter och specifika hederstitlar eller familjeroller,  
> **så att** jag har full koll på logistiken och kan ge specifika gäster en särställning.
- [ ] **Skapa gäst med kontaktinfo:** Kunna lägga till gäster med förnamn, efternamn, valfri e-post samt valfritt telefonnummer.
- [ ] **Tilldela titlar:** Kunna sätta en titel/roll på en gäst (`Maid of Honor`, `Best Man`, `Förälder`, `Syskon`, `Barn`).
- [ ] **Partner-koppling:** Kunna koppla ihop två gäster som `Partner` (för framtida bordsplaceringsval).
- [ ] **Vän- och Undvik-koppling:** Kunna sätta kopplingar för `Friend` samt `Avoid` (personer som inte får sitta ihop).

#### 3. Konfigurera Algoritmregler (Kryssrutor)
> **Som ett** brudpar,  
> **vill jag** själv kunna kryssa i vilka regler som algoritmen ska prioritera (så som partners, bekanta eller hederstitlar),  
> **så att** programmet inte fattar beslut åt mig utan anpassar sig efter våra önskemål.
- [ ] **Toggle för partners:** En kryssruta för om algoritmen *måste* sätta partners precis bredvid varandra eller ej.
- [ ] **Toggle för bekanta:** En kryssruta för om algoritmen *måste* se till att alla känner minst en person vid sitt bord eller ej.
- [ ] **Regel för titlar:** Ett val (t.ex. dropdown eller radiobuttons) där admin bestämmer om gäster med titlar ska sitta vid `Samma bord som brudparet`, `1 närliggande bord`, eller om det `Inte spelar någon roll`.

#### 4. Automatisk Bordsplacering & Manuella Ändringar
> **Som ett** brudpar,  
> **vill jag** att systemet automatiskt placerar alla gäster utifrån de regler vi har kryssat i, samt tillåta att jag flyttar runt stolar efteråt,  
> **så att** jag sparar tid men behåller full kontroll.
- [ ] **Algoritm-trigg:** En knapp som kör algoritmen och placerar ut gäster baserat på de förvalda kryssrutornas regler.
- [ ] **Manuell Drag-and-Drop:** Möjlighet att dra och släppa en specifik gäst från en stol till en another efter algoritmkörningen.
- [ ] **Visuell varning:** En stol eller ett helt bord lyser rött om bordet blir överfullt eller om en *aktiverad* algoritmregel bryts under manuell flytt.
- [ ] **Lås funktion:** Möjlighet för admin att "låsa" specifika gäster på fasta stolar innan algoritmen körs.

#### 5. Hantera RSVP-deadline & Manuella Overrides
> **Som ett** brudpar,  
> **vill jag** kunna sätta en sista svarsdag och manuellt kunna ändra status på gäster som missat den,  
> **så att** listorna hålls uppdaterade och korrekta inför matbeställningen.
- [ ] **Automatisk strykning:** Systemet markerar gäster som inte svarat i tid som strukna när `rsvp_deadline` har passerats.
- [ ] **Exkludering:** Strukna gäster blir visuellt genomstrukna i adminlistan och tas automatiskt bort från bordsplaceringen.
- [ ] **Manuell återställning:** Admin har en knapp för att manuellt "återuppliva" en struken gäst, ändra status till "Kommer" samt lägga till matval.

#### 6. Anpassa Landningssida (Egen Bild)
> **Som ett** brudpar,  
> **vill jag** själv kunna ladda upp en personlig bild till landningssidan från adminpanelen,  
> **så att** jag slipper be en utvecklare uppdatera sidan och kan göra den personlig när jag själv vill.
- [ ] **Bilduppladdning:** Gränssnitt i adminpanelen för att välja och ladda upp en bild (PNG/JPEG).
- [ ] **Lagring & URL:** Bilden sparas i molnlagringen och dess URL sparas i databasen under aktuellt `wedding_id`.
- [ ] **Omedelbar uppdatering:** När bilden är sparad uppdateras landningssidan i realtid vid nästa sidomladdning för både brudpar och gäster.

#### 7. Dataexport (JSON & PDF)
> **Som ett** brudpar,  
> **vill jag** kunna exportera bordsplaceringen och matlistan till PDF och JSON,  
> **så att** jag kan printa ut kartan till lokalen, skicka allergilistan till kockarna och dela projektfilen mellan våra enheter.
- [ ] **JSON-backup:** Export och import av en lokal `.json`-fil med all bröllopsdata för enkel delning och backup utan inloggning.
- [ ] **PDF-bordskarta:** Generera en högupplöst, utskriftsvänlig PDF över den visuella bordskartan.
- [ ] **PDF-kökslista:** Generera en strukturerad PDF-lista sorterad per bord som visar gästernas namn och eventuell specialkost/allergier för kockarna.

---

### 🥂 Bröllopsgäst (Mobilgränssnitt / App)

#### 8. Digital Inbjudan & Anpassad Landningssida
> **Som en** bröllopsgäst,  
> **vill jag** mötas av en välkomstsida som antingen visar en bild på brudparet eller en fin standardbild samt praktisk info,  
> **så att** sidan känns personlig och ger mig rätt information inför dagen.
- [ ] **Mobiloptimering:** Hela gästgränssnittet anpassar sig sömlöst för små mobilskärmar.
- [ ] **Dynamiska Omslagsbild:** Landningssidan visar brudparets uppladdade bild. Om ingen bild laddats upp (`cover_image_url` är null) används en snygg inbyggd standardbild.
- [ ] **Dagens tidslinje:** En interaktiv och tydlig översikt över bröllopsdagens schema och hålltider.
- [ ] **Karthantering:** Integrerade djuplänkar som automatiskt öppnar Google Maps på Android och Apple Maps på iOS vid klick på adresser.

#### 9. Friktionsfri RSVP, Telefon & Kostregistrering
> **Som en** bröllopsgäst,  
> **vill jag** kunna anmäla om jag kommer, ange mitt telefonnummer samt matpreferenser genom att bara söka på mitt namn,  
> **så att** jag slipper skapa ett användarkonto eller komma ihåg ett lösenord.
- [ ] **Namnsökning:** Gästen möts av en sökruta där de skriver in sitt namn för att hitta sin inbjudan.
- [ ] **Närvaroval:** När namnet matchas visas enkla knappar for "Jag kommer" respektive "Jag kan tyvärr inte".
- [ ] **Kost & Kontaktformulär:** Om gästen väljer "Jag kommer" expanderas ett formulär där de kan skriva in allergier/specialkost samt lämna sitt telefonnummer (frivilligt).

#### 10. Hitta min plats på bröllopsdagen
> **Som en** bröllopsgäst på bröllopsdagen,  
> **vill jag** snabbt kunna söka efter mitt namn i mobilen och se var jag ska sitta,  
> **så att** det inte blir trängsel och förvirring vid den fysiska bordskartan i lokalen.
- [ ] **Sökbar placering:** När admin har publicerat bordsplaceringen blir den synlig och sökbar i gästvyn.
- [ ] **Visuell indikering:** När gästen söker på sitt eget namn zoomar vyn in på rätt bord, och deras specifika stol/bord lyser upp eller blinkar.