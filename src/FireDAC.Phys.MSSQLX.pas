{-------------------------------------------------------------------------------
  FireDAC.Phys.MSSQLX

  A custom ODBC-based FireDAC driver for Microsoft SQL Server.

  DriverID : MSSQLX
  Base     : TFDPhysODBCDriverBase / TFDPhysODBCConnectionBase
  Target   : Delphi 12 Athens (Studio 23.0), Win32 + Win64
  ODBC     : Microsoft ODBC Driver 18/17 for SQL Server

  ---------------------------------------------------------------------------
  ACCURACY NOTE -- please read before changing anything
  ---------------------------------------------------------------------------
  Every signature in this unit was checked against one of two sources:

    [SRC]  C:\Program Files (x86)\Embarcadero\Studio\23.0\source\data\firedac\
           FireDAC.Phys.pas  -- real shipped source
    [DOC]  Embarcadero DocWiki per-member signature pages (Athens)

  FireDAC.Phys.ODBCBase.pas ships as .dcu only, so the ODBC layer is covered
  by [DOC] rather than source. Where a hook there had to be overridden anyway,
  the signature was recovered rather than guessed -- marked [PROBE] below:

    - RTTI, for anything public. TFDPhysMSSQLMetadata.Create came out of the
      shipped RTTI complete with all nine parameter names.
    - The compiler, for anything protected. Calling a method with deliberately
      wrong arguments makes the error message name the expected type, and
      arity falls out of "too many/not enough actual parameters".

  Still left alone as genuinely unverified: GetODBCDriver, GetODBCAdvanced,
  GetODBCConnectStringKeywords, GetConnParams, GetExceptionClass,
  FindBestDriver.

  An earlier draft guessed at signatures instead. If you extend this unit, use
  one of the two techniques above -- do not guess.

  An earlier draft of this unit guessed at those signatures. Four of the
  guesses were wrong in ways that prevent compilation:

    1. InternalCreateConnection takes AConnHost: TFDPhysConnectionHost.
    2. TFDPhysConnection.Create takes (ADriverObj, AConnHost) -- two args.
    3. InternalExecuteDirect takes (const ASQL: String; ATransaction:
       TFDPhysTransaction) -- two args.
    4. The RDBMS kind constant is TFDRDBMSKinds.MSSQL, a record constant.
       There is no "mkMSSQL" enum; the mk* prefix belongs to metadata kinds.

  If you extend this unit, verify before you override.
-------------------------------------------------------------------------------}

unit FireDAC.Phys.MSSQLX;

interface

uses
  System.Classes, System.SysUtils,
  FireDAC.Stan.Intf, FireDAC.Stan.Error, FireDAC.Stan.Consts,
  FireDAC.DatS,
  FireDAC.Phys, FireDAC.Phys.Intf, FireDAC.Phys.ODBCBase,
  FireDAC.Phys.SQLGenerator, FireDAC.Phys.MSSQLMeta;

const
  S_FD_MSSQLXId   = 'MSSQLX';
  S_FD_MSSQLXDesc = 'Microsoft SQL Server (MSSQLX custom driver)';

  /// <summary>Default ODBC driver applied by the driver link component.</summary>
  S_MSSQLX_DefaultODBCDriver = 'ODBC Driver 18 for SQL Server';

  // ---- MSSQLX-specific connection definition parameters --------------------
  // Read via ConnectionDef.AsString[...], which is the accessor FireDAC's own
  // code uses (FireDAC.Phys.pas:3880).
  //
  // TFDPhysODBCDriverBase understands only these connection params:
  //   Database, User_Name, Password, LoginTimeout, DataSource (DSN),
  //   ODBCDriver, ODBCAdvanced.
  // It has NO concept of Server, OSAuthent or MARS -- those belong to
  // FireDAC's own MSSQL driver, not to the generic ODBC base. Setting
  // Params.Values['Server'] directly on an MSSQLX connection reaches nothing:
  // TFDPhysODBCDriverBase itself would silently ignore it, failing with
  // "Neither DSN nor SERVER keyword supplied". Server, Database and OSAuthent
  // work anyway because TFDPhysMSSQLXDriver.BuildODBCConnectString below
  // reads all three and injects them; FireDAC.Phys.MSSQLXDef exposes them as
  // typed properties on top of that. MARS is not among them -- pass
  // MARS_Connection through ODBCAdvanced, as MSSQLXDemo.dpr does.
  S_MSSQLX_LockTimeout         = 'LockTimeout';
  S_MSSQLX_IsolationLevel      = 'IsolationLevel';
  S_MSSQLX_ApplySessionProfile = 'ApplySessionProfile';

type
  TFDPhysMSSQLXDriver     = class;
  TFDPhysMSSQLXConnection = class;
  TFDPhysMSSQLXCommand    = class;

  {-----------------------------------------------------------------------------
    Design-time / run-time link component.

    This is how the ODBC driver name and advanced connect-string options get
    pinned, rather than by overriding GetODBCDriver. ODBCDriver and
    ODBCAdvanced are published properties of TFDPhysODBCBaseDriverLink -- fully
    documented public API, so no guessing required.

    Per Embarcadero's docs: link properties must be set before the first
    connection is opened through this driver. Afterwards the driver instance is
    loaded and ignores changes.
  -----------------------------------------------------------------------------}
  TFDPhysMSSQLXDriverLink = class(TFDPhysODBCBaseDriverLink)
  protected
    // [SRC] FireDAC.Phys.pas -- TFDPhysDriverLink declares this as an
    // INSTANCE method: function GetBaseDriverID: String; virtual;
    // (Note it is a *class* function on TFDPhysDriver. Different classes,
    // different signatures -- an easy one to get backwards.)
    function GetBaseDriverID: String; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  {-----------------------------------------------------------------------------
    Driver. One instance per DriverID, created lazily by the physical manager.
  -----------------------------------------------------------------------------}
  TFDPhysMSSQLXDriver = class(TFDPhysODBCDriverBase)
  protected
    // [SRC] class function GetBaseDriverID: String; virtual;
    class function GetBaseDriverID: String; override;

    // [SRC] class function GetBaseDriverDesc: String; virtual;
    class function GetBaseDriverDesc: String; override;

    // [SRC] class function GetRDBMSKind: TFDRDBMSKind; virtual;
    /// <summary>
    ///   Selects SQL Server dialect throughout the Stan/Comp layers -- SQL
    ///   generation, identifier quoting, OFFSET/FETCH paging, escape handling.
    /// </summary>
    class function GetRDBMSKind: TFDRDBMSKind; override;

    // [SRC] class function GetConnectionDefParamsClass: TFDConnectionDefParamsClass; virtual;
    //
    // Must be overridden. TFDPhysDriver's implementation is ASSERT(False) +
    // Result := nil, and TFDPhysODBCDriverBase does NOT override it -- every
    // shipped concrete driver supplies its own (e.g. TFDPhysMSAccessDriver ->
    // TFDPhysMSAccConnectionDefParams). Without this, the first assignment to
    // TFDConnection.Params.DriverID access-violates inside System.@ClassCreate:
    // TFDPhysConnectionDefParamsFactory.CreateObject (FireDAC.Phys.pas:1709)
    // constructs from the nil class reference this returns.
    //
    // Returns TFDPhysMSSQLXConnectionDefParams (FireDAC.Phys.MSSQLXDef), not
    // the generic base -- that unit is also what stops the IDE's Connection
    // Editor / DriverID property editor inserting a phantom
    // "FireDAC.Phys.MSSQLXDef" uses reference: every shipped driver has one,
    // by convention, and the editor assumes ours does too.
    class function GetConnectionDefParamsClass: TFDConnectionDefParamsClass; override;

    // [SRC] function InternalCreateConnection(
    //         AConnHost: TFDPhysConnectionHost): TFDPhysConnection; virtual; abstract;
    function InternalCreateConnection(
      AConnHost: TFDPhysConnectionHost): TFDPhysConnection; override;

    // [SRC] function GetConnParams(AKeys: TStrings; AParams: TFDDatSTable):
    //         TFDDatSTable; virtual; -- FireDAC.Phys.pas:175/2093.
    //
    // This is the row list the IDE's Connection Editor (right-click a
    // TFDConnection at design time) uses to build its property grid, and it
    // reads back from that SAME grid on OK/Apply -- confirmed by calling it
    // directly against a live driver instance rather than guessed. Before
    // this override, calling it returned exactly 8 rows: DriverID, Pooled,
    // Database, User_Name, Password, MonitorBy, ODBCAdvanced, LoginTimeout
    // (the last two from TFDPhysODBCDriverBase's own override; everything
    // else from TFDPhysDriver's default). None of FireDAC.Phys.MSSQLXDef's
    // properties were in that list -- which is exactly why opening the
    // editor and clicking OK wiped them: the editor only knows to write back
    // what it displayed, and it never displayed them.
    function GetConnParams(AKeys: TStrings; AParams: TFDDatSTable): TFDDatSTable;
      override;

  public
    // [PROBE] function BuildODBCConnectString(
    //           const AConnectionDef: IFDStanConnectionDef): String; virtual;
    //
    // Signature recovered with the compiler (ODBCBase is .dcu only) and
    // confirmed virtual by overriding it. Declared public to match the base --
    // putting it under protected compiles but narrows visibility (H2269).
    //
    // Exists to repair two kinds of gap in the base implementation:
    //
    // 1. PWD is not brace-escaped (UID is). Dumping the string built for user
    //    "us;er" / password "pa;ss" gives:
    //
    //      DRIVER=...;UID={us;er};PWD=pa;ss;APP=...
    //
    //    A password containing ';' therefore terminates the keyword early --
    //    SQL Server receives only the text before the ';' and reports "Login
    //    failed for user X", which reads like a permissions problem when the
    //    credential is merely truncated. The same password works in SSMS and
    //    sqlcmd, so this is a genuinely nasty one to track down in the field.
    //
    // 2. Several FireDAC.Phys.MSSQLXDef properties (Server, OSAuthent, MARS,
    //    Encrypt, TrustServerCertificate, ApplicationName; Database is
    //    inherited but has the same problem) have no meaning to the base at
    //    all -- either it does not recognise the key, or it recognises it and
    //    drops it from the connect string regardless (Database's failure mode:
    //    connects fine, silently lands on the login's default catalog). Every
    //    one of these was diagnosed by dumping the actual string the base
    //    built and comparing it to what SQL Server needs, not guessed. This
    //    method reads each such property's underlying key -- ONLY when the
    //    caller actually set it, per AppendBoolIfTrue/AppendIfAbsent below --
    //    and injects the ODBC keyword the base left out. See
    //    FireDAC.Phys.MSSQLXDef's header for what each property means.
    function BuildODBCConnectString(
      const AConnectionDef: IFDStanConnectionDef): String; override;
  end;

  {-----------------------------------------------------------------------------
    Connection. One per physical session.
  -----------------------------------------------------------------------------}
  TFDPhysMSSQLXConnection = class(TFDPhysODBCConnectionBase)
  private
    function ParamStr(const AName, ADefault: String): String;
    function ParamBool(const AName: String; ADefault: Boolean): Boolean;
    function ParamInt(const AName: String; ADefault: Integer): Integer;
    procedure ApplySessionProfile;
  protected
    // [SRC] procedure InternalConnect; virtual; abstract;
    //       (TFDPhysODBCConnectionBase provides the implementation.)
    //
    // The session profile runs here rather than in SetupConnection because
    // ordering is guaranteed: after inherited returns, the ODBC connection is
    // established and can execute SQL. SetupConnection is also virtual and
    // documented, but where it sits relative to SQLDriverConnect is not, and
    // running SET statements against a not-yet-open handle would fail.
    procedure InternalConnect; override;

    // [SRC] function InternalCreateCommand: TFDPhysCommand; virtual; abstract;
    function InternalCreateCommand: TFDPhysCommand; override;

    // [SRC] function InternalGetCurrentSchema: String; virtual;
    function InternalGetCurrentSchema: String; override;

    // [SRC] function InternalCreateMetadata: TObject; virtual; abstract;
    // [SRC] function InternalCreateCommandGenerator(
    //         const ACommand: IFDPhysCommand): TFDPhysCommandGenerator; virtual; abstract;
    //
    // Both are abstract on TFDPhysConnection and are NOT implemented by
    // TFDPhysODBCConnectionBase -- these are the two W1020 warnings this unit
    // has been emitting since day one. Leaving them unimplemented raises
    // EAbstractError the moment a connection is opened.
    function InternalCreateMetadata: TObject; override;
    function InternalCreateCommandGenerator(
      const ACommand: IFDPhysCommand): TFDPhysCommandGenerator; override;
  end;

  {-----------------------------------------------------------------------------
    Command.

    TFDPhysODBCCommand already implements prepare, parameter binding for every
    FireDAC type, array DML, fetch loops and blob streaming. This descendant is
    a seam, nothing more. If you never put anything in it, delete it and have
    InternalCreateCommand return TFDPhysODBCCommand.Create(Self).

    [DOC] TFDPhysODBCCommand is confirmed to exist in FireDAC.Phys.ODBCBase.
  -----------------------------------------------------------------------------}
  TFDPhysMSSQLXCommand = class(TFDPhysODBCCommand)
  end;

implementation

uses
  System.StrUtils,
  System.Variants,
  // Implementation-only on both sides: this unit's interface never mentions
  // FireDAC.Phys.MSSQLXDef (GetConnectionDefParamsClass's declared return
  // type is the generic TFDConnectionDefParamsClass), and MSSQLXDef's
  // interface never mentions this unit either -- it only needs the S_MSSQLX_*
  // constants inside its property bodies. Two units needing each other only
  // from their implementation sections is not the illegal kind of circular
  // reference; only two INTERFACE sections referencing each other is.
  FireDAC.Phys.MSSQLXDef;


{ ---------------------------------------------------------------------------- }
{ TFDPhysMSSQLXDriverLink                                                       }
{ ---------------------------------------------------------------------------- }

constructor TFDPhysMSSQLXDriverLink.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Pin the ODBC driver here instead of overriding GetODBCDriver. Driver 18
  // defaults Encrypt=yes (17 defaulted to no), so state the intent explicitly
  // rather than inheriting whichever default the installed driver happens to
  // carry. Callers can still override per connection via the ODBCDriver and
  // ODBCAdvanced connection-def params.
  ODBCDriver := S_MSSQLX_DefaultODBCDriver;
end;

function TFDPhysMSSQLXDriverLink.GetBaseDriverID: String;
begin
  Result := S_FD_MSSQLXId;
end;

{ ---------------------------------------------------------------------------- }
{ TFDPhysMSSQLXDriver                                                           }
{ ---------------------------------------------------------------------------- }

class function TFDPhysMSSQLXDriver.GetBaseDriverID: String;
begin
  Result := S_FD_MSSQLXId;
end;

class function TFDPhysMSSQLXDriver.GetBaseDriverDesc: String;
begin
  Result := S_FD_MSSQLXDesc;
end;

class function TFDPhysMSSQLXDriver.GetRDBMSKind: TFDRDBMSKind;
begin
  // [SRC] FireDAC.Phys.SQLGenerator.pas uses TFDRDBMSKinds.MSSQL -- a record
  // constant, not an enum literal.
  Result := TFDRDBMSKinds.MSSQL;
end;

class function TFDPhysMSSQLXDriver.GetConnectionDefParamsClass: TFDConnectionDefParamsClass;
begin
  Result := TFDPhysMSSQLXConnectionDefParams;
end;

// Appends 'KEYWORD=value' to a connect string being built, unless the caller
// has already supplied that keyword by hand (checked case-insensitively,
// since ODBC keywords are). Guards against emitting SERVER= twice when a
// caller still composes it into ODBCAdvanced manually, as MSSQLXDemo.dpr
// does -- ODBC's handling of a duplicate keyword is not something to rely on.
procedure AppendIfAbsent(var AConnStr: String; const AKeyword, AValue: String);
begin
  if (AValue = '') or (Pos(AnsiUpperCase(AKeyword) + '=',
                            AnsiUpperCase(AConnStr)) > 0) then
    Exit;
  AConnStr := AConnStr + ';' + AKeyword + '=' + AValue;
end;

// Shared by OSAuthent/MARS/Encrypt/TrustServerCertificate: all four are
// one-directional (True injects the keyword; False and untouched are
// indistinguishable and both mean "inject nothing"), so the same three lines
// would otherwise repeat four times.
procedure AppendBoolIfTrue(const AConnectionDef: IFDStanConnectionDef;
  var AConnStr: String; const AParamName, AKeyword, AKeywordValue: String);
begin
  if AConnectionDef.Params.IndexOfName(AParamName) < 0 then
    Exit;
  if MatchText(Trim(AConnectionDef.AsString[AParamName]),
      ['1', 'Y', 'YES', 'T', 'TRUE', 'ON']) then
    AppendIfAbsent(AConnStr, AKeyword, AKeywordValue);
end;

function TFDPhysMSSQLXDriver.BuildODBCConnectString(
  const AConnectionDef: IFDStanConnectionDef): String;
var
  sRaw: String;
begin
  Result := inherited BuildODBCConnectString(AConnectionDef);

  if (AConnectionDef = nil) or (AConnectionDef.Params = nil) then
    Exit;

  // Server: the base has no concept of it at all. Database: the base has an
  // inherited property for it but never puts it in the connect string, so
  // this fires even though Params.IndexOfName('Database') already succeeds --
  // presence in Params is not the same as presence in what actually reaches
  // the driver manager.
  if AConnectionDef.Params.IndexOfName('Server') >= 0 then
    AppendIfAbsent(Result, 'SERVER', AConnectionDef.AsString['Server']);
  if AConnectionDef.Params.IndexOfName(S_FD_ConnParam_Common_Database) >= 0 then
    AppendIfAbsent(Result, 'DATABASE',
      AConnectionDef.AsString[S_FD_ConnParam_Common_Database]);

  // OSAuthent: only ever ADDS Trusted_Connection=yes, never Trusted_Connection
  // =no. A dropped TFDConnection authenticates nothing by default -- no
  // Trusted_Connection, no UserName/Password -- and the ODBC driver's own
  // response to that is to attempt SQL auth with a blank username, surfacing
  // as "Login failed for user ''" only once Open is called, with nothing in
  // the Object Inspector or at compile time to explain why. OSAuthent=False
  // and OSAuthent left untouched are therefore treated identically here:
  // inject nothing, and let UserName/Password (already handled correctly,
  // see the PWD escaping below) drive SQL auth exactly as before this
  // property existed.
  AppendBoolIfTrue(AConnectionDef, Result, 'OSAuthent', 'Trusted_Connection', 'yes');

  // MARS, Encrypt, TrustServerCertificate: same one-directional shape as
  // OSAuthent. See FireDAC.Phys.MSSQLXDef's property comments for what each
  // means and, for TrustServerCertificate, why it is not something to set as
  // a reflex.
  AppendBoolIfTrue(AConnectionDef, Result, 'MARS', 'MARS_Connection', 'yes');
  AppendBoolIfTrue(AConnectionDef, Result, 'Encrypt', 'Encrypt', 'yes');
  AppendBoolIfTrue(AConnectionDef, Result, 'TrustServerCertificate',
    'TrustServerCertificate', 'yes');

  if AConnectionDef.Params.IndexOfName('ApplicationName') >= 0 then
    AppendIfAbsent(Result, 'APP', AConnectionDef.AsString['ApplicationName']);

  if AConnectionDef.Params.IndexOfName(S_FD_ConnParam_Common_Password) < 0 then
    Exit;

  sRaw := AConnectionDef.AsString[S_FD_ConnParam_Common_Password];
  if sRaw = '' then
    Exit;

  // Leave a value the caller already escaped alone rather than nesting braces.
  if (sRaw[1] = '{') and (sRaw[Length(sRaw)] = '}') then
    Exit;

  // Substitute the exact literal the base emitted rather than parsing the
  // string back apart -- once "PWD=pa;ss;APP=..." exists there is no way to
  // tell where the password ended. Anchoring on 'PWD=' + the known raw value
  // is unambiguous. Only the first match is replaced, and the base emits PWD
  // ahead of ODBCAdvanced, so a PWD the caller put in ODBCAdvanced is safe.
  //
  // Braced unconditionally: it is harmless for values that need no escaping,
  // and cheaper than tracking ODBC's full special-character set. A literal
  // '}' inside a braced value is doubled, per the ODBC rule.
  Result := StringReplace(
    Result,
    'PWD=' + sRaw,
    'PWD={' + StringReplace(sRaw, '}', '}}', [rfReplaceAll]) + '}',
    []);
end;

function TFDPhysMSSQLXDriver.InternalCreateConnection(
  AConnHost: TFDPhysConnectionHost): TFDPhysConnection;
begin
  // [SRC] constructor TFDPhysConnection.Create(
  //         ADriverObj: TFDPhysDriver; AConnHost: TFDPhysConnectionHost); virtual;
  // [DOC] TFDPhysODBCConnectionBase.Create overrides with the same signature.
  Result := TFDPhysMSSQLXConnection.Create(Self, AConnHost);
end;

function TFDPhysMSSQLXDriver.GetConnParams(AKeys: TStrings;
  AParams: TFDDatSTable): TFDDatSTable;
begin
  // inherited first: keeps DriverID/Pooled/Database/User_Name/Password/
  // MonitorBy/ODBCAdvanced/LoginTimeout exactly as the base and
  // TFDPhysODBCDriverBase already define them. Everything added below is a
  // FireDAC.Phys.MSSQLXDef property that inherited does not already cover.
  //
  // Row shape confirmed from TFDPhysDriver.GetConnParams's own source
  // (FireDAC.Phys.pas:2093): [ID, Name, Type, DefVal, Caption, LoginIndex].
  // Type codes '@S'/'@P'/'@L'/'@I' (string/password/boolean/integer) and the
  // semicolon-list-as-dropdown convention are both taken directly from that
  // source, not guessed. LoginIndex -1 for all of these: that field is only
  // for fields that also appear in the LoginPrompt dialog, which none of
  // these are.
  Result := inherited GetConnParams(AKeys, AParams);

  Result.Rows.Add([Unassigned, 'Server', '@S', '', 'Server', -1]);
  Result.Rows.Add([Unassigned, 'OSAuthent', '@L', S_FD_False, 'OSAuthent', -1]);
  Result.Rows.Add([Unassigned, 'MARS', '@L', S_FD_False, 'MARS', -1]);
  Result.Rows.Add([Unassigned, 'Encrypt', '@L', S_FD_False, 'Encrypt', -1]);
  Result.Rows.Add([Unassigned, 'TrustServerCertificate', '@L', S_FD_False,
    'TrustServerCertificate', -1]);
  Result.Rows.Add([Unassigned, 'ApplicationName', '@S', '', 'ApplicationName', -1]);
  Result.Rows.Add([Unassigned, 'ODBCDriver', '@S', S_MSSQLX_DefaultODBCDriver,
    'ODBCDriver', -1]);
  Result.Rows.Add([Unassigned, S_MSSQLX_LockTimeout, '@I', '', 'LockTimeout', -1]);
  // Leading ';' gives an initial blank choice, matching what GetIsolationLevel
  // treats as ilUnspecified -- an empty stored value, not the literal word
  // "Unspecified".
  Result.Rows.Add([Unassigned, S_MSSQLX_IsolationLevel,
    ';READ UNCOMMITTED;READ COMMITTED;REPEATABLE READ;SNAPSHOT;SERIALIZABLE',
    '', 'IsolationLevel', -1]);
  // Default shown is True, not False like the others: GetApplySessionProfile
  // treats an unset key as True (the profile applies unless explicitly turned
  // off), so True is what actually reflects the unset behavior here.
  Result.Rows.Add([Unassigned, S_MSSQLX_ApplySessionProfile, '@L', S_FD_True,
    'ApplySessionProfile', -1]);
end;

{ ---------------------------------------------------------------------------- }
{ TFDPhysMSSQLXConnection                                                       }
{ ---------------------------------------------------------------------------- }

function TFDPhysMSSQLXConnection.ParamStr(const AName, ADefault: String): String;
var
  oDef: IFDStanConnectionDef;
begin
  // [SRC] property ConnectionDef: IFDStanConnectionDef read GetConnectionDef;
  // [SRC] FireDAC.Phys.pas:3880 -- ConnectionDef.AsString[S_FD_ConnParam_...]
  //
  // The IndexOfName guard is deliberate. Whether AsString[] returns '' or
  // raises for a name that is not present in the def is NOT documented, and
  // the MSSQLX-specific params below are all optional. Params is a TStrings
  // descendant -- that is what makes the standard TFDConnection.Params.Values
  // idiom work -- so IndexOfName is safe to lean on.
  oDef := ConnectionDef;
  if (oDef = nil) or (oDef.Params = nil) or (oDef.Params.IndexOfName(AName) < 0) then
    Exit(ADefault);
  Result := oDef.AsString[AName];
  if Result = '' then
    Result := ADefault;
end;

function TFDPhysMSSQLXConnection.ParamBool(const AName: String;
  ADefault: Boolean): Boolean;
var
  s: String;
begin
  s := Trim(ParamStr(AName, ''));
  if s = '' then
    Result := ADefault
  else
    Result := MatchText(s, ['1', 'Y', 'YES', 'T', 'TRUE', 'ON']);
end;

function TFDPhysMSSQLXConnection.ParamInt(const AName: String;
  ADefault: Integer): Integer;
begin
  Result := StrToIntDef(Trim(ParamStr(AName, '')), ADefault);
end;

procedure TFDPhysMSSQLXConnection.ApplySessionProfile;
var
  iLockTimeout: Integer;
  sIsolation: String;

  procedure Exec(const ASQL: String);
  begin
    // [SRC] procedure InternalExecuteDirect(
    //         const ASQL: String; ATransaction: TFDPhysTransaction); virtual; abstract;
    // [SRC] FireDAC.Phys.pas:4227 shows the idiom: pass TransactionObj, which
    //       is a public property of TFDPhysConnection.
    InternalExecuteDirect(ASQL, TransactionObj);
  end;

begin
  // ANSI settings. These need to match what SSMS uses, or identical queries
  // behave differently between your app and your DBA's session -- especially
  // around NULL comparison and trailing-space padding.
  Exec('SET ANSI_NULLS ON;' +
       'SET ANSI_PADDING ON;' +
       'SET ANSI_WARNINGS ON;' +
       'SET ANSI_NULL_DFLT_ON ON;' +
       'SET CONCAT_NULL_YIELDS_NULL ON;' +
       'SET QUOTED_IDENTIFIER ON;' +
       'SET NUMERIC_ROUNDABORT OFF;');

  // ARITHABORT ON is the highest-value line in this unit.
  //
  // SQL Server caches separate execution plans for ARITHABORT ON and OFF.
  // SSMS connects with it ON; ODBC clients historically connect with it OFF.
  // That mismatch is the root cause of the perennial "runs in 200ms in SSMS,
  // 40 seconds from Delphi" report -- same query, same server, different
  // cached plan. It is also required for indexed views, filtered indexes and
  // computed-column indexes to be usable from this connection.
  Exec('SET ARITHABORT ON;');

  iLockTimeout := ParamInt(S_MSSQLX_LockTimeout, -1);
  if iLockTimeout >= 0 then
    Exec(Format('SET LOCK_TIMEOUT %d;', [iLockTimeout]));

  // A parameter rather than a hardcoded value: different applications sharing
  // this driver legitimately want different isolation.
  sIsolation := Trim(ParamStr(S_MSSQLX_IsolationLevel, ''));
  if sIsolation <> '' then
    if MatchText(sIsolation, ['READ UNCOMMITTED', 'READ COMMITTED',
                              'REPEATABLE READ', 'SNAPSHOT', 'SERIALIZABLE']) then
      Exec('SET TRANSACTION ISOLATION LEVEL ' + sIsolation + ';')
    else
      // Whitelisted because this value reaches T-SQL as literal text and
      // cannot be parameterised.
      raise Exception.CreateFmt('Invalid %s value: %s',
        [S_MSSQLX_IsolationLevel, sIsolation]);
end;

procedure TFDPhysMSSQLXConnection.InternalConnect;
begin
  inherited InternalConnect;

  // Caveat worth knowing: this runs on physical connect. FireDAC's pool reuses
  // physical connections, and BeforeReuse/AfterReuse on TFDPhysConnection are
  // non-virtual, so there is no supported hook to re-apply the profile on pool
  // checkout. In practice that is fine -- session SET state persists on the
  // physical connection -- but it does mean application code that issues its
  // own SET statements can leave state behind for the next borrower.
  if ParamBool(S_MSSQLX_ApplySessionProfile, True) then
    ApplySessionProfile;
end;

function TFDPhysMSSQLXConnection.InternalCreateCommand: TFDPhysCommand;
begin
  // [SRC] constructor TFDPhysCommand.Create(AConnection: TFDPhysConnection); virtual;
  Result := TFDPhysMSSQLXCommand.Create(Self);
end;

function TFDPhysMSSQLXConnection.InternalCreateMetadata: TObject;
var
  nServerVer, nClientVer: UInt64;
begin
  // [RTTI] TFDPhysMSSQLMetadata.Create(const AConnectionObj: TFDPhysConnection;
  //          ACatalogCaseSensitive, ASchemaCaseSensitive, ASchemaCaseInsSearch,
  //          ANameDoubleQuote, AMSDriver: Boolean;
  //          AServerVersion, AClientVersion: UInt64;
  //          AColumnOriginProvided: Boolean);
  //
  // Signature recovered from the shipped RTTI, not guessed -- FireDAC.Phys.
  // MSSQLMeta ships as a .dcu, so there is no source to read.
  //
  // [DCU] TFDPhysODBCConnectionBase.GetVersions(var AServerVersion,
  //          AClientVersion: UInt64) -- protected, so reachable from here.
  nServerVer := 0;
  nClientVer := 0;
  GetVersions(nServerVer, nClientVer);

  Result := TFDPhysMSSQLMetadata.Create(
    Self,
    False,      // ACatalogCaseSensitive -- SQL Server follows collation, and
    False,      // ASchemaCaseSensitive     the stock collations are CI.
    True,       // ASchemaCaseInsSearch
    False,      // ANameDoubleQuote -- quote with [], which is valid regardless
                //   of QUOTED_IDENTIFIER. Using " would make metadata quoting
                //   depend on session state ApplySessionProfile sets later.
    True,       // AMSDriver -- this driver targets Microsoft's ODBC driver.
    nServerVer,
    nClientVer,
    True);      // AColumnOriginProvided -- MS ODBC supplies
                //   SQL_DESC_BASE_TABLE_NAME / _BASE_COLUMN_NAME, which is what
                //   lets FireDAC generate updates for a joined SELECT.
end;

function TFDPhysMSSQLXConnection.InternalCreateCommandGenerator(
  const ACommand: IFDPhysCommand): TFDPhysCommandGenerator;
begin
  // [SRC] FireDAC.Phys.SQLGenerator.pas:190
  //       constructor TFDPhysCommandGenerator.Create(const ACommand: IFDPhysCommand);
  Result := TFDPhysMSSQLCommandGenerator.Create(ACommand);
end;

function TFDPhysMSSQLXConnection.InternalGetCurrentSchema: String;
begin
  Result := inherited InternalGetCurrentSchema;
  if Result = '' then
    Result := 'dbo';
end;

{ ---------------------------------------------------------------------------- }
{ Registration                                                                  }
{ ---------------------------------------------------------------------------- }

initialization
  // [SRC] procedure TFDPhysManager.RegisterDriverClass(ADriverClass: TClass);
  // [DOC] IFDPhysManager.RegisterDriverClass / UnregisterDriverClass
  //       (note the asymmetric casing -- Register / Unregister)
  //
  // Registers the driver CLASS. The manager instantiates it on the first
  // connection with DriverID=MSSQLX.
  //
  // This unit must be linked into the binary. Reference it explicitly from
  // your .dpr uses clause -- an otherwise-unused unit gets smart-linked away
  // and you get [FireDAC][Phys]-302 "Driver MSSQLX is not linked into
  // application" at runtime.
  FDPhysManager.RegisterDriverClass(TFDPhysMSSQLXDriver);

finalization
  FDPhysManager.UnregisterDriverClass(TFDPhysMSSQLXDriver);

end.
