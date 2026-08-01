# Writing a Custom ODBC-Based FireDAC Driver for SQL Server

**Target:** Delphi 11/12/13, Win32 + Win64
**New DriverID:** `MSSQLX`
**Base classes:** `TFDPhysODBCDriverBase` / `TFDPhysODBCConnectionBase` (unit `FireDAC.Phys.ODBCBase`, package `FireDACCommonODBC290.bpl` in Athens)

---

## 1. Read this first: where the ground truth lives

FireDAC's physical layer is **almost entirely protected and undocumented**. DocWiki lists member *names* and per-member signatures, but almost no descriptions.

Checking Studio 23.0 on this machine, **only five FireDAC units ship as source**:

```
C:\Program Files (x86)\Embarcadero\Studio\23.0\source\data\firedac\
    FireDAC.Phys.pas               <- TFDPhysDriver/Connection/Command/DriverLink  ← the important one
    FireDAC.Phys.SQLGenerator.pas
    FireDAC.Phys.SQLPreprocessor.pas
    FireDAC.Phys.IBWrapper.pas
    FireDAC.Comp.QBE.pas
```

`FireDAC.Phys.ODBCBase.pas` and `FireDAC.Phys.MSSQL.pas` are **.dcu only** — you cannot read them. C++Builder `.hpp` headers would carry the full declarations, but they're only present if C++Builder is installed.

So there are exactly two sources of truth:

| Marker | Source | Covers |
|---|---|---|
| **[SRC]** | `FireDAC.Phys.pas` | Base layer: `TFDPhysDriver`, `TFDPhysConnection`, `TFDPhysCommand`, `TFDPhysDriverLink`, `TFDPhysManager` |
| **[DOC]** | DocWiki per-member signature pages | ODBC layer: `TFDPhysODBCDriverBase`, `TFDPhysODBCConnectionBase` |

**Anything not covered by one of those two should not be overridden.** The accompanying source unit follows that rule strictly — where a hook was tempting but unverifiable (`GetODBCDriver`, `GetODBCAdvanced`, `GetODBCConnectStringKeywords`, `GetConnParams`, `GetExceptionClass`, `FindBestDriver`), it uses documented public API instead.

### Signatures that are easy to get wrong

These four were verified from `[SRC]` and each one is a compile error if guessed:

```pascal
// TFDPhysDriver — note the AConnHost parameter
function InternalCreateConnection(
  AConnHost: TFDPhysConnectionHost): TFDPhysConnection; virtual; abstract;

// TFDPhysConnection — two arguments
constructor Create(ADriverObj: TFDPhysDriver;
  AConnHost: TFDPhysConnectionHost); virtual;

// TFDPhysConnection — two arguments; pass the public TransactionObj property
procedure InternalExecuteDirect(const ASQL: String;
  ATransaction: TFDPhysTransaction); virtual; abstract;

// The RDBMS kind is a RECORD CONSTANT, not an enum literal.
// There is no "mkMSSQL" — the mk* prefix belongs to metadata kinds
// (mkTables, mkIndexes, mkProcs...).
Result := TFDRDBMSKinds.MSSQL;
```

One more asymmetry worth internalising: `GetBaseDriverID` is a **class** function on `TFDPhysDriver` but an **instance** function on `TFDPhysDriverLink`. Same name, same unit, different binding.

---

## 2. Why write one at all

FireDAC already ships `MSSQL`. Legitimate reasons to add your own DriverID:

| Reason | Notes |
|---|---|
| Pin a specific ODBC driver + defaults | Ship `ODBC Driver 18 for SQL Server` with `Encrypt=yes` and your TLS policy baked in, so no connection definition can get it wrong. |
| Mandatory session state | Force `SET ARITHABORT ON`, isolation level, `LOCK_TIMEOUT`, `CONTEXT_INFO`, app-name tagging on every connect. |
| Multi-tenant / routing | Rewrite `Server` from a tenant key, inject `ApplicationIntent=ReadOnly` for reporting connections. |
| Different capability profile | Turn MARS off fleet-wide, change how identity values are fetched, adjust metadata catalog/schema defaults. |
| Coexistence | Your driver and the stock `MSSQL` driver can be registered simultaneously — useful for phased migration. |

If you only need behavioural tweaks, `TFDPhysMSSQLDriverLink` + connection params is cheaper. A new DriverID is worth it when you want the behaviour to be **non-negotiable and centrally owned**.

---

## 3. Class map

```
IFDPhysManager  (FireDAC.Phys.Intf)          — global registry, FDPhysManager
  └─ registers ──> TFDPhysDriver class
                     │
TFDPhysDriver (FireDAC.Phys)                 — one instance per DriverID
  └─ TFDPhysODBCDriverBase (ODBCBase)        — owns ODBC env handle, connect-string builder
       └─ TFDPhysMSSQLXDriver                <-- YOU

TFDPhysConnection (FireDAC.Phys)             — one per session
  └─ TFDPhysODBCConnectionBase (ODBCBase)    — owns SQLHDBC, ODBC error mapping
       └─ TFDPhysMSSQLXConnection            <-- YOU

TFDPhysCommand (FireDAC.Phys)
  └─ TFDPhysODBCCommand (ODBCBase)           — full SQLPrepare/SQLBindParameter/SQLFetch impl
       └─ TFDPhysMSSQLXCommand               <-- YOU (optional; usually thin)

TFDPhysODBCTransaction (ODBCBase)            — usually reuse as-is
TFDPhysDriverLink (FireDAC.Phys)
  └─ TFDPhysODBCBaseDriverLink (ODBCBase)    — design-time component
       └─ TFDPhysMSSQLXDriverLink            <-- YOU
```

The reason the ODBC route is dramatically cheaper than a from-scratch driver: **`TFDPhysODBCCommand` already implements the entire command lifecycle** — prepare, parameter binding for every FireDAC data type, array DML, fetch loops, blob streaming, cursor positioning. You inherit thousands of lines of tested code. A from-scratch `TFDPhysCommand` means writing all of that yourself.

---

## 4. The driver class — what to override

Only four overrides are needed, and all four are `[SRC]`-verified:

| Member | Verified signature | Purpose |
|---|---|---|
| `GetBaseDriverID` | `class function GetBaseDriverID: String; virtual;` | Your DriverID. **The one mandatory override.** |
| `GetBaseDriverDesc` | `class function GetBaseDriverDesc: String; virtual;` | Name shown in the connection editor. |
| `GetRDBMSKind` | `class function GetRDBMSKind: TFDRDBMSKind; virtual;` | Return `TFDRDBMSKinds.MSSQL` so the Stan/Comp layers pick SQL Server SQL generation, escaping and `OFFSET/FETCH` paging. **Getting this wrong is the #1 cause of weird custom-driver bugs** — you get syntax errors in generated SQL you never wrote. |
| `InternalCreateConnection` | `function InternalCreateConnection(AConnHost: TFDPhysConnectionHost): TFDPhysConnection; virtual; abstract;` | Factory for your connection class. |

Also on `TFDPhysDriver`, if you want it: `class function GetConnectionDefParamsClass: TFDConnectionDefParamsClass; virtual;`.

### What to leave alone, and what to use instead

`GetODBCDriver`, `GetODBCAdvanced`, `GetODBCConnectStringKeywords`, `GetConnParams` and `FindBestDriver` all exist on `TFDPhysODBCDriverBase` — DocWiki confirms the member list, and publishes signatures for two of them:

```pascal
procedure GetODBCConnectStringKeywords(AKeywords: TStrings); virtual;
function GetConnParams(AKeys: TStrings; AParams: TFDDatSTable): TFDDatSTable; override;
```

But their *semantics* aren't published, and that's the problem:

- `GetODBCConnectStringKeywords` — is `AKeywords` a `Name=Keyword` mapping, or a bare keyword list? Guess wrong and connections still open while your custom params are silently dropped. That's a worse failure than a compile error.
- `GetConnParams` — `AParams` is a `TFDDatSTable` whose column layout is undocumented. Building rows against the wrong layout corrupts the connection editor rather than failing loudly.

**Use the documented public path instead.** `TFDPhysODBCBaseDriverLink` publishes `ODBCDriver` and `ODBCAdvanced`; set them in your link component's constructor. Anything you'd have injected via keyword mapping goes through the `ODBCAdvanced` connection param, which the base class appends to the connect string verbatim:

```pascal
Conn.Params.Values['ODBCAdvanced'] := 'APP=MyApp;Encrypt=yes;MARS_Connection=yes';
```

Same result, no guessing. Revisit the overrides only if you get access to `FireDAC.Phys.MSSQL.pas` (a C++Builder install would give you `FireDAC.Phys.ODBCBase.hpp`, which carries the full declarations).

### Connect-string keywords for `msodbcsql18`

Useful whether you set them via `ODBCAdvanced` or eventually via keyword mapping:

```
SERVER  DATABASE  UID  PWD  APP  WSID  LANGUAGE
MARS_Connection  Encrypt  TrustServerCertificate
ApplicationIntent  MultiSubnetFailover  Trusted_Connection
```

Two items that bite people on Driver 18 specifically:

- **`Encrypt` defaults to `yes`** in msodbcsql18 (it was `no` in 17). Connections that worked for years start failing with certificate-chain errors after an upgrade. Decide your policy explicitly rather than inheriting the default.
- **`TrustServerCertificate=yes` disables validation entirely.** It is the usual quick fix and the usual security hole. Prefer installing the server certificate into the Windows trust store; if you must allow the bypass, make it an opt-in parameter that is off by default, as the sample code does.

---

## 5. The connection class — what to override

All `[SRC]`-verified on `TFDPhysConnection` (`TFDPhysODBCConnectionBase` supplies the implementations):

| Member | Verified signature | Purpose |
|---|---|---|
| `InternalConnect` | `procedure InternalConnect; virtual; abstract;` | Override, call `inherited`, then do post-connect work. |
| `InternalCreateCommand` | `function InternalCreateCommand: TFDPhysCommand; virtual; abstract;` | Factory for your command class. |
| `InternalCreateTransaction` | `function InternalCreateTransaction: TFDPhysTransaction; virtual; abstract;` | Inherit `TFDPhysODBCTransaction` unless you need snapshot semantics. |
| `InternalGetCurrentCatalog` / `InternalGetCurrentSchema` | `function: String; virtual;` | Default catalog/schema. |
| `InternalExecuteDirect` | `procedure InternalExecuteDirect(const ASQL: String; ATransaction: TFDPhysTransaction); virtual; abstract;` | Fire-and-forget SQL. Pass the public `TransactionObj` property. |
| `GetLastAutoGenValue` | `function GetLastAutoGenValue(const AName: String = ''): Variant; virtual;` | Identity retrieval. **Use `SCOPE_IDENTITY()`, not `@@IDENTITY`** — `@@IDENTITY` returns values generated by triggers on other tables. |
| `ConnectionDef` | `property ConnectionDef: IFDStanConnectionDef read GetConnectionDef;` | Read params via `ConnectionDef.AsString['Name']` — the accessor FireDAC's own code uses. |

`SetupConnection` (`[DOC]`: `procedure SetupConnection; virtual;`) also exists on `TFDPhysODBCConnectionBase` and looks like the obvious hook. The sample code uses `InternalConnect` instead, because **where `SetupConnection` sits relative to `SQLDriverConnect` isn't documented** — and running `SET` statements against a not-yet-open handle would fail. After `inherited InternalConnect` returns, the connection is provably live.

### A note on connection pooling

`BeforeReuse` / `AfterReuse` exist on `TFDPhysConnection` but are **not virtual**, so there's no supported hook to re-apply session state on pool checkout. In practice this is fine — `SET` state persists on the physical connection — but application code that issues its own `SET` statements can leave state behind for the next borrower. Worth knowing before you rely on the profile being intact.

### Session settings worth forcing on connect

```sql
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ANSI_NULL_DFLT_ON ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
```

`ARITHABORT ON` deserves special mention. SQL Server keeps **separate cached plans** for `ARITHABORT ON` and `OFF`. SSMS connects with it ON; ODBC/OLE DB clients historically connect with it OFF. This is the classic "the query is instant in SSMS and takes 40 seconds from my app" report — same query, same server, different cached plan. Forcing it ON in the driver removes an entire category of support ticket. It is also **required** for indexed views, filtered indexes, and computed-column indexes to be usable.

`LOCK_TIMEOUT` and `TRANSACTION ISOLATION LEVEL` are also good candidates, but make them parameters rather than hardcoding — different apps on the same driver legitimately want different values.

---

## 6. Registration and lifecycle

Verified on `IFDPhysManager` (unit `FireDAC.Phys.Intf`): ✅ `RegisterDriverClass` and ✅ `UnregisterDriverClass` — note the asymmetric casing, `Unregister` with a lowercase `r`.

```pascal
initialization
  FDPhysManager.RegisterDriverClass(TFDPhysMSSQLXDriver);
finalization
  FDPhysManager.UnregisterDriverClass(TFDPhysMSSQLXDriver);
end.
```

Lifecycle:

1. Unit initialization registers the **class**, not an instance.
2. First connection with `DriverID=MSSQLX` causes the manager to instantiate the driver and call `Load` → `InternalLoad`, which loads the ODBC client library.
3. `InternalCreateConnection` produces a connection per `TFDConnection.Open`.
4. `SetupConnection` runs inside the connect sequence.
5. `Unload` / `InternalUnload` on shutdown.

**Ordering matters.** The unit must be linked into the binary before any connection is opened. Reference it explicitly in your `.dpr` uses clause — a unit that nothing references gets smart-linked away, and you get a `[FireDAC][Phys]-302 Driver MSSQLX is not linked into application` error at runtime.

Do not put the driver unit in a runtime package that loads lazily, unless you also register it eagerly.

---

## 7. Design-time link component

`TFDPhysODBCBaseDriverLink` gives you `ODBCDriver` and `ODBCAdvanced` published properties. Your descendant needs `GetBaseDriverID` returning `'MSSQLX'` so the IDE associates the component with your driver, plus `Register` in a design-time package to put it on the palette.

Per Embarcadero's own documentation on `TFDPhysODBCBaseDriverLink`: **link component properties must be set before the first connection is opened through that driver.** Changing them afterwards has no effect until the driver is unloaded.

---

## 8. Testing checklist

Driver bugs surface as data corruption, not crashes, so test breadth matters more than depth.

- [ ] Connect / disconnect / reconnect, both SQL auth and `OSAuthent=Yes`
- [ ] `Encrypt=yes` against a server with a self-signed cert (should fail), then with the cert trusted (should succeed)
- [ ] Round-trip every type: `nvarchar(max)`, `varbinary(max)`, `datetime2(7)`, `datetimeoffset`, `decimal(38,10)`, `uniqueidentifier`, `bit`, `sql_variant`, `xml`, `hierarchyid`
- [ ] Unicode: non-BMP characters (emoji) through `nvarchar` — surrogate pairs are a common breakage point
- [ ] Parameterised `SELECT`, output parameters, and a stored proc returning both a result set and a return value
- [ ] Multiple result sets from one batch
- [ ] Array DML / batch insert of 10k rows
- [ ] `SCOPE_IDENTITY()` retrieval after insert into a table with an insert trigger on a *different* table
- [ ] Nested transactions and savepoints
- [ ] MARS on and off, with two open cursors on one connection
- [ ] Metadata: `GetTableNames`, `GetFieldNames` across schemas and across databases
- [ ] Connection pooling under concurrency — confirm `SetupConnection` runs on pooled reuse, not just first connect
- [ ] Long-running query cancellation (`AbortJob`)
- [ ] `SET ARITHABORT` actually applied — verify with `SELECT SESSIONPROPERTY('ARITHABORT')`
- [ ] Both Win32 and Win64 (ODBC driver bitness must match; a 64-bit app cannot use a 32-bit DSN)

---

## 9. Known sharp edges

**ODBC bitness.** Win32 and Win64 have separate ODBC administrators (`%SystemRoot%\SysWOW64\odbcad32.exe` vs `%SystemRoot%\System32\odbcad32.exe`) and separate DSN registries. Prefer DSN-less connection strings to avoid this entirely.

**"Connection is busy with results for another hstmt."** Classic SQL Server ODBC error, raised when a second statement executes while the first still has unfetched rows. Fixed by enabling MARS, or by ensuring FireDAC fully fetches (`FetchOptions.Mode = fmAll`) before issuing the next command. If you disable MARS in your driver, expect this and document it.

**`GetRDBMSKind` returning the wrong value** silently changes SQL generation everywhere — `TFDQuery` paging, `TFDUpdateSQL` generation, escape-sequence handling. Symptoms look like random SQL syntax errors on operations you never touched.

**Trailing-space semantics.** `ANSI_PADDING` affects `char`/`varchar` comparison. Set it consistently or comparisons behave differently between your app and SSMS.

**Delphi package version suffix.** The ODBC base package is versioned (`FireDACCommonODBC290.bpl` for Athens/12). Your design-time package's `requires` clause is version-bound; a runtime package built for 12 will not load in 13.

---

## 10. Files in this deliverable

| File | Contents |
|---|---|
| `FireDAC.Phys.MSSQLX.pas` | Driver, connection, command, transaction wiring, driver link, registration |
| `MSSQLXDemo.dpr` | Console program: register, connect, query, verify session settings |

There are nine overrides in the unit and every one carries a `[SRC]` or `[DOC]` comment naming where its signature was verified. Nothing is guessed. If you add an override and can't mark it `[SRC]` or `[DOC]`, that's the signal to find another way to get the behaviour.

---

**Sources**

- [FireDAC.Phys.ODBCBase (unit)](https://docwiki.embarcadero.com/Libraries/Athens/en/FireDAC.Phys.ODBCBase)
- [TFDPhysODBCDriverBase Methods](https://docwiki.embarcadero.com/Libraries/Athens/en/FireDAC.Phys.ODBCBase.TFDPhysODBCDriverBase_Methods)
- [TFDPhysODBCConnectionBase Methods](https://docwiki.embarcadero.com/Libraries/Athens/en/FireDAC.Phys.ODBCBase.TFDPhysODBCConnectionBase_Methods)
- [TFDPhysODBCDriverBase.GetConnParams](https://docwiki.embarcadero.com/Libraries/Athens/en/FireDAC.Phys.ODBCBase.TFDPhysODBCDriverBase.GetConnParams)
- [TFDPhysODBCDriverBase.GetODBCConnectStringKeywords](https://docwiki.embarcadero.com/Libraries/Athens/en/FireDAC.Phys.ODBCBase.TFDPhysODBCDriverBase.GetODBCConnectStringKeywords)
- [TFDPhysODBCConnectionBase.SetupConnection](https://docwiki.embarcadero.com/Libraries/Athens/en/FireDAC.Phys.ODBCBase.TFDPhysODBCConnectionBase.SetupConnection)
- [IFDPhysManager Methods](https://docwiki.embarcadero.com/Libraries/Athens/en/FireDAC.Phys.Intf.IFDPhysManager_Methods)
- [TFDPhysODBCBaseDriverLink](https://docwiki.embarcadero.com/Libraries/Athens/en/FireDAC.Phys.ODBCBase.TFDPhysODBCBaseDriverLink)
- [Configuring Drivers (FireDAC)](https://docwiki.embarcadero.com/RADStudio/Athens/en/Configuring_Drivers_(FireDAC))
