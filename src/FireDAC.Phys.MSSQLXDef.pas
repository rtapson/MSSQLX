{-------------------------------------------------------------------------------
  FireDAC.Phys.MSSQLXDef -- strongly-typed connection-def params for MSSQLX.

  Every shipped FireDAC driver follows one naming convention: driver unit
  FireDAC.Phys.<X>, companion params unit FireDAC.Phys.<X>Def (MSAccDef,
  PGDef, MySQLDef, IBDef, ADSDef, SQLiteDef -- all present as .dcu in
  lib\Win32\release). The IDE's DriverID property editor assumes every driver
  follows it: the moment you pick MSSQLX in the Object Inspector, it inserts a
  'FireDAC.Phys.MSSQLXDef' reference into your uses clause whether or not the
  file exists. Before this unit existed that reference was a phantom -- a
  file-not-found error the instant you tried to compile. This unit is what
  makes it a real one.

  [SRC confirmed via RTTI against the shipped TFDConnectionDefParams /
  TFDPhysMSAccConnectionDefParams (FireDAC.Phys.MSAccDef.dcu), both .dcu-only:
    - TFDConnectionDefParams descends from TFDStringList. Concrete params
      classes add properties as plain wrappers over the inherited Values[]
      indexer; MSAcc's Def class declares no fields, no constructor override,
      properties only.
    - The base already carries Database: TFileName, UserName, Password as
      inherited properties -- do not redeclare them here.]

  Two categories of property below:

    1. Passthrough onto keys TFDPhysODBCDriverBase genuinely understands
       (ODBCDriver, ODBCAdvanced, LoginTimeout) or onto MSSQLX's own params
       (LockTimeout, IsolationLevel, ApplySessionProfile). These need nothing
       extra -- Values[] already reaches the connect string.

    2. Server and OSAuthent. Neither is inherited (neither is a universal
       FireDAC concept), and TFDPhysODBCDriverBase's connect-string builder
       does not understand either on its own:
         - Server: setting it used to fail outright with "Neither DSN nor
           SERVER keyword supplied".
         - OSAuthent: with nothing set, the base's connect string carries no
           authentication mode at all, so ODBC attempts SQL auth with a blank
           username -- "Login failed for user ''" the moment Open is called,
           traced back to a dropped TFDConnection with nothing but Server/
           Database configured.
       (The inherited Database silently landed on the login's default catalog
       instead of the requested one, the same class of gap as Server -- also
       diagnosed against a real SQL Server instance.)
       TFDPhysMSSQLXDriver.BuildODBCConnectString now reads all of these and
       injects SERVER=/DATABASE=/Trusted_Connection= when the caller has not
       already composed them into ODBCAdvanced by hand, so these properties
       are not just visible in the Object Inspector -- they are verified to
       work; see the driver unit for the injection logic.

  MARS, Encrypt, TrustServerCertificate and ApplicationName follow the exact
  same pattern as Server/OSAuthent: not inherited, not understood by the base
  on their own, made real only because BuildODBCConnectString reads them.
  MARS/Encrypt/TrustServerCertificate are one-directional like OSAuthent --
  True injects the keyword, False and untouched are indistinguishable and
  both mean "inject nothing, let ODBC's own default apply." There is
  deliberately no way to force e.g. Encrypt=no through these properties; that
  narrow case still goes through ODBCAdvanced directly, same as before this
  unit existed.
-------------------------------------------------------------------------------}

unit FireDAC.Phys.MSSQLXDef;

interface

uses
  FireDAC.Stan.Intf;

type
  {-----------------------------------------------------------------------------
    Mirrors the whitelist TFDPhysMSSQLXConnection.ApplySessionProfile already
    enforces at runtime (MatchText against 'READ UNCOMMITTED' .. 'SERIALIZABLE').
    Turning it into an enum here means the Object Inspector offers exactly
    those five choices instead of a free-text field that only fails when the
    connection is opened. ilUnspecified means "do not issue SET TRANSACTION
    ISOLATION LEVEL at all" -- SQL Server's own default, not a sixth isolation
    level.
  -----------------------------------------------------------------------------}
  TFDMSSQLXIsolationLevel = (
    ilUnspecified,
    ilReadUncommitted,
    ilReadCommitted,
    ilRepeatableRead,
    ilSnapshot,
    ilSerializable);

  {-----------------------------------------------------------------------------
    TFDPhysMSSQLXConnectionDefParams

    Returned by TFDPhysMSSQLXDriver.GetConnectionDefParamsClass. Instantiated
    by TFDPhysConnectionDefParamsFactory.CreateObject (FireDAC.Phys.pas:1709)
    the moment a TFDConnection's Params.DriverID is set to MSSQLX -- this is
    also, not coincidentally, the exact call that used to access-violate
    before GetConnectionDefParamsClass was implemented at all.
  -----------------------------------------------------------------------------}
  TFDPhysMSSQLXConnectionDefParams = class(TFDConnectionDefParams)
  private
    function GetServer: String;
    procedure SetServer(const AValue: String);
    function GetOSAuthent: Boolean;
    procedure SetOSAuthent(AValue: Boolean);
    function GetMARS: Boolean;
    procedure SetMARS(AValue: Boolean);
    function GetEncrypt: Boolean;
    procedure SetEncrypt(AValue: Boolean);
    function GetTrustServerCertificate: Boolean;
    procedure SetTrustServerCertificate(AValue: Boolean);
    function GetApplicationName: String;
    procedure SetApplicationName(const AValue: String);
    function GetODBCDriver: String;
    procedure SetODBCDriver(const AValue: String);
    function GetODBCAdvanced: String;
    procedure SetODBCAdvanced(const AValue: String);
    function GetLoginTimeout: Integer;
    procedure SetLoginTimeout(AValue: Integer);
    function GetLockTimeout: Integer;
    procedure SetLockTimeout(AValue: Integer);
    function GetIsolationLevel: TFDMSSQLXIsolationLevel;
    procedure SetIsolationLevel(AValue: TFDMSSQLXIsolationLevel);
    function GetApplySessionProfile: Boolean;
    procedure SetApplySessionProfile(AValue: Boolean);
  published
    // Published, not public: the Object Inspector reads classic RTTI
    // (published members only), not the extended RTTI System.Rtti exposes for
    // public members too. TFDConnectionDefParams's ancestry runs through
    // TPersistent, which bakes in {$M+} for every descendant, so no extra
    // directive is needed here -- just the right section.
    //
    // See the unit header: not inherited, and only meaningful because
    // BuildODBCConnectString now knows to read it.
    //
    // stored False on every property below: without it, Delphi's DFM writer
    // emits each one as its own top-level "Params.Xxx = ..." line, and those
    // always stream BEFORE "Params.Strings" (list-content properties always
    // stream last). Params.Strings is what carries DriverID, and Params only
    // becomes this class -- the one that HAS a Server/OSAuthent/etc. property
    // -- once DriverID has been applied. Read back in that order, "Params.
    // Server = '.'" lands on the still-generic base Params object and fails
    // with "Property Server does not exist" -- reproduced by
    // demo\Vcl\SQLXDataModule.dfm, which streams cleanly once these are
    // stored False and the redundant individual lines are stripped from the
    // .dfm, leaving Values[] (via Strings) as the single source of
    // persistence. The console demo (MSSQLXDemo.dpr) never hit this: it sets
    // Params.DriverID in code before touching any typed property.
    property Server: String read GetServer write SetServer stored False;

    // Same category as Server: not inherited, meaningless without the
    // matching BuildODBCConnectString support. Reads False whether OSAuthent
    // was left untouched or explicitly set False -- both mean the same thing
    // to BuildODBCConnectString (inject nothing, so ODBC's own default takes
    // over), which is exactly the ODBC default that produces "Login failed
    // for user ''" the moment it's reached with no UserName/Password either:
    // a dropped TFDConnection + TFDPhysMSSQLXDriverLink authenticates nothing
    // by default, and neither the Object Inspector nor a compile error says
    // so. Set True for Windows-integrated auth; leave it and set UserName/
    // Password for SQL auth, which already worked correctly before this
    // property existed.
    property OSAuthent: Boolean read GetOSAuthent write SetOSAuthent stored False;

    // Same True-only-injects pattern as OSAuthent. MARS_Connection is the
    // real ODBC keyword; MARS is the name used here to match how FireDAC's
    // own (non-ODBC) MSSQL driver refers to the same concept.
    property MARS: Boolean read GetMARS write SetMARS stored False;

    // ODBC Driver 18 for SQL Server defaults Encrypt=yes; Driver 17 defaulted
    // to no. Leaving this untouched means whichever driver is installed picks
    // its own default -- set True to require encryption explicitly, rather
    // than depending on which driver version happens to be on the machine.
    property Encrypt: Boolean read GetEncrypt write SetEncrypt stored False;

    // Security note, not a formality: this is encrypted-but-unauthenticated,
    // the standard way of quietly defeating what TLS is for. It exists to
    // unblock a self-signed certificate in dev/test. The correct fix for that
    // is installing the server's certificate into the Windows trust store,
    // not leaving this on. Never set it True as a reflex, and never in
    // anything that talks to a production server.
    property TrustServerCertificate: Boolean
      read GetTrustServerCertificate write SetTrustServerCertificate stored False;

    // Reaches SQL Server as APP=, visible in sys.dm_exec_sessions.program_name
    // -- worth setting on any connection you might later need to find in a
    // session list or a DBA's query of who is connected.
    property ApplicationName: String
      read GetApplicationName write SetApplicationName stored False;

    // Standard ODBC-base params (documented in FireDAC.Phys.MSSQLX's header),
    // exposed the same way MSAcc's own Def class exposes them.
    property ODBCDriver: String read GetODBCDriver write SetODBCDriver stored False;
    property ODBCAdvanced: String read GetODBCAdvanced write SetODBCAdvanced stored False;
    property LoginTimeout: Integer read GetLoginTimeout write SetLoginTimeout stored False;

    // MSSQLX-specific, consumed by ApplySessionProfile.
    property LockTimeout: Integer read GetLockTimeout write SetLockTimeout stored False;
    property IsolationLevel: TFDMSSQLXIsolationLevel
      read GetIsolationLevel write SetIsolationLevel stored False;
    property ApplySessionProfile: Boolean
      read GetApplySessionProfile write SetApplySessionProfile stored False;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  FireDAC.Phys.MSSQLX;

{ TFDPhysMSSQLXConnectionDefParams }

function TFDPhysMSSQLXConnectionDefParams.GetServer: String;
begin
  Result := Values['Server'];
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetServer(const AValue: String);
begin
  Values['Server'] := AValue;
end;

function TFDPhysMSSQLXConnectionDefParams.GetOSAuthent: Boolean;
begin
  // No unset-defaults-to-True special case here, unlike ApplySessionProfile --
  // an unset key has to read False, because False is what BuildODBCConnectString
  // treats as "inject nothing," and unset genuinely means nothing was chosen.
  // Claiming True by default would misrepresent ODBC's own behavior, which is
  // to attempt SQL auth with a blank username, not Windows auth.
  Result := MatchText(Trim(Values['OSAuthent']), ['1', 'Y', 'YES', 'T', 'TRUE', 'ON']);
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetOSAuthent(AValue: Boolean);
begin
  Values['OSAuthent'] := IfThen(AValue, 'Yes', 'No');
end;

function TFDPhysMSSQLXConnectionDefParams.GetMARS: Boolean;
begin
  Result := MatchText(Trim(Values['MARS']), ['1', 'Y', 'YES', 'T', 'TRUE', 'ON']);
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetMARS(AValue: Boolean);
begin
  Values['MARS'] := IfThen(AValue, 'Yes', 'No');
end;

function TFDPhysMSSQLXConnectionDefParams.GetEncrypt: Boolean;
begin
  Result := MatchText(Trim(Values['Encrypt']), ['1', 'Y', 'YES', 'T', 'TRUE', 'ON']);
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetEncrypt(AValue: Boolean);
begin
  Values['Encrypt'] := IfThen(AValue, 'Yes', 'No');
end;

function TFDPhysMSSQLXConnectionDefParams.GetTrustServerCertificate: Boolean;
begin
  Result := MatchText(Trim(Values['TrustServerCertificate']),
    ['1', 'Y', 'YES', 'T', 'TRUE', 'ON']);
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetTrustServerCertificate(AValue: Boolean);
begin
  Values['TrustServerCertificate'] := IfThen(AValue, 'Yes', 'No');
end;

function TFDPhysMSSQLXConnectionDefParams.GetApplicationName: String;
begin
  Result := Values['ApplicationName'];
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetApplicationName(const AValue: String);
begin
  Values['ApplicationName'] := AValue;
end;

function TFDPhysMSSQLXConnectionDefParams.GetODBCDriver: String;
begin
  Result := Values['ODBCDriver'];
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetODBCDriver(const AValue: String);
begin
  Values['ODBCDriver'] := AValue;
end;

function TFDPhysMSSQLXConnectionDefParams.GetODBCAdvanced: String;
begin
  Result := Values['ODBCAdvanced'];
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetODBCAdvanced(const AValue: String);
begin
  Values['ODBCAdvanced'] := AValue;
end;

function TFDPhysMSSQLXConnectionDefParams.GetLoginTimeout: Integer;
begin
  Result := StrToIntDef(Values['LoginTimeout'], 0);
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetLoginTimeout(AValue: Integer);
begin
  Values['LoginTimeout'] := IntToStr(AValue);
end;

function TFDPhysMSSQLXConnectionDefParams.GetLockTimeout: Integer;
begin
  Result := StrToIntDef(Values[S_MSSQLX_LockTimeout], -1);
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetLockTimeout(AValue: Integer);
begin
  Values[S_MSSQLX_LockTimeout] := IntToStr(AValue);
end;

function TFDPhysMSSQLXConnectionDefParams.GetIsolationLevel: TFDMSSQLXIsolationLevel;
var
  s: String;
begin
  // Kept in exact lockstep with the whitelist in
  // TFDPhysMSSQLXConnection.ApplySessionProfile -- if that whitelist ever
  // changes, this mapping has to change with it.
  s := Trim(Values[S_MSSQLX_IsolationLevel]);
  if SameText(s, 'READ UNCOMMITTED') then Result := ilReadUncommitted
  else if SameText(s, 'READ COMMITTED') then Result := ilReadCommitted
  else if SameText(s, 'REPEATABLE READ') then Result := ilRepeatableRead
  else if SameText(s, 'SNAPSHOT') then Result := ilSnapshot
  else if SameText(s, 'SERIALIZABLE') then Result := ilSerializable
  else Result := ilUnspecified;
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetIsolationLevel(
  AValue: TFDMSSQLXIsolationLevel);
const
  // Index matches TFDMSSQLXIsolationLevel's declaration order exactly.
  LEVEL_TEXT: array [TFDMSSQLXIsolationLevel] of String = (
    '', 'READ UNCOMMITTED', 'READ COMMITTED', 'REPEATABLE READ', 'SNAPSHOT',
    'SERIALIZABLE');
begin
  Values[S_MSSQLX_IsolationLevel] := LEVEL_TEXT[AValue];
end;

function TFDPhysMSSQLXConnectionDefParams.GetApplySessionProfile: Boolean;
var
  s: String;
begin
  // Matches TFDPhysMSSQLXConnection.ParamBool's own "unset -> True" default:
  // the profile applies unless someone explicitly turns it off.
  s := Trim(Values[S_MSSQLX_ApplySessionProfile]);
  Result := (s = '') or MatchText(s, ['1', 'Y', 'YES', 'T', 'TRUE', 'ON']);
end;

procedure TFDPhysMSSQLXConnectionDefParams.SetApplySessionProfile(AValue: Boolean);
begin
  Values[S_MSSQLX_ApplySessionProfile] := IfThen(AValue, 'Yes', 'No');
end;

end.
