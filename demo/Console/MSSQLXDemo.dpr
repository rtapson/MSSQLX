{-------------------------------------------------------------------------------
  MSSQLXDemo -- smoke test for the MSSQLX custom FireDAC driver.

  Build:  dcc32 MSSQLXDemo.dpr        (or dcc64)
  Run:    MSSQLXDemo <server> <database> [user] [password]
          MSSQLXDemo .\SQLEXPRESS AdventureWorks
          MSSQLXDemo tcp:sql01,1433 Sales appuser s3cret

  Checks, in order:
    1. the driver class registered and the manager can see it;
    2. a connection actually opens through it;
    3. InternalConnect applied the session profile -- verified by reading
       SESSIONPROPERTY('ARITHABORT') back off the server rather than trusting
       that the SET executed;
    4. parameter binding and fetching work end to end.

  Step 3 is the one to keep. A driver that connects but silently skips the
  session profile looks completely healthy until a plan-cache problem surfaces
  in production months later.

  Two things about connection parameters that are easy to get wrong:

    - Configure below sets Server/Database/OSAuthent/MARS/Encrypt/
      TrustServerCertificate/ApplicationName through FireDAC.Phys.MSSQLXDef's
      typed properties, not by hand-composing ODBCAdvanced. None of these mean
      anything to the generic ODBC base by itself -- it has no Server/
      OSAuthent/MARS concept at all (those belong to FireDAC's own MSSQL
      driver), and while it does accept Database, it silently drops it from
      the connect string, landing on the login's default catalog. They work
      here only because TFDPhysMSSQLXDriver.BuildODBCConnectString reads each
      property and injects the ODBC keyword the base left out. Step 4 still
      asserts DB_NAME() rather than trusting Database was honoured, because
      that failure mode is otherwise invisible.

    - A TFDPhysMSSQLXDriverLink must exist before the first Open. It is what
      supplies the ODBC driver name, and without it the connect string carries
      no DRIVER= at all: "Data source name not found and no default driver
      specified".
-------------------------------------------------------------------------------}

program MSSQLXDemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  FireDAC.Comp.Client,
  FireDAC.Phys,
  FireDAC.Phys.Intf,
  FireDAC.Phys.ODBCBase,
  // Must be referenced explicitly or the linker drops it and the driver never
  // registers. This one line is the whole installation step.
  FireDAC.Phys.MSSQLX in '..\..\src\FireDAC.Phys.MSSQLX.pas',
  FireDAC.Phys.MSSQLXDef in '..\..\src\FireDAC.Phys.MSSQLXDef.pas';

procedure Report(const AFmt: String; const AArgs: array of const);
begin
  Writeln(Format(AFmt, AArgs));
end;

/// <summary>Confirms the driver class reached the manager's registry.</summary>
procedure VerifyDriverRegistered;
var
  oMeta: IFDPhysManagerMetadata;
  i: Integer;
  bFound: Boolean;
begin
  // RegisterDriverClass only adds to the manager's in-memory driver-class
  // list, not to GetDriverDefs (the persisted driver-definitions store), so
  // the class list has to be queried via IFDPhysManagerMetadata instead.
  Supports(FDPhysManager, IFDPhysManagerMetadata, oMeta);

  bFound := False;
  for i := 0 to oMeta.GetDriverCount - 1 do
    if SameText(oMeta.GetDriverID(i), S_FD_MSSQLXId) then
    begin
      bFound := True;
      Break;
    end;

  if not bFound then
    raise Exception.CreateFmt(
      'DriverID %s is not registered. Is FireDAC.Phys.MSSQLX linked in?',
      [S_FD_MSSQLXId]);
  Report('[1/4] Driver %s registered.', [S_FD_MSSQLXId]);
end;

procedure Configure(AConn: TFDConnection;
  const AServer, ADatabase, AUser, APassword: String);
var
  oParams: TFDPhysMSSQLXConnectionDefParams;
begin
  AConn.Params.DriverID := S_FD_MSSQLXId;

  // FireDAC.Phys.MSSQLXDef's typed properties, not raw ODBCAdvanced surgery.
  // Server and Database (Database is inherited) reach the connect string only
  // because TFDPhysMSSQLXDriver.BuildODBCConnectString reads them -- the
  // generic ODBC base does not recognise Server at all and silently drops
  // Database, landing on the login's default catalog instead of the
  // requested one. This is Params, cast to the strongly-typed class
  // GetConnectionDefParamsClass hands back; casting is required because
  // TFDConnection.Params is declared as the generic base type.
  oParams := AConn.Params as TFDPhysMSSQLXConnectionDefParams;
  oParams.Server := AServer;
  AConn.Params.Database := ADatabase;
  oParams.ApplicationName := 'MSSQLXDemo';

  // ODBC Driver 18 defaults Encrypt=yes (17 defaulted to no); set True to be
  // explicit rather than depend on which driver version is installed.
  oParams.Encrypt := True;
  oParams.MARS := True;

  // TrustServerCertificate=True keeps the connection encrypted but skips
  // validating who is on the other end -- it defeats the part of TLS that
  // stops an interceptor from impersonating the server. It is here because
  // this is a smoke test that has to run against dev instances with
  // self-signed certificates. Do not carry this into production code: install
  // the server certificate into the Windows trust store and drop this line.
  oParams.TrustServerCertificate := True;

  // Credentials are the exception: unlike Server and Database, User_Name and
  // Password really do reach the connect string as UID=/PWD= via the base
  // itself. Verified by connecting with SQL auth against a Windows-auth-only
  // instance -- SQL Server answered "Login failed for user 'mssqlx_probe'",
  // naming the user it was actually sent. Passed raw: escaping them is the
  // driver's job, not this caller's -- the base brace-escapes UID, and
  // TFDPhysMSSQLXDriver.BuildODBCConnectString does the same for PWD, which
  // the base leaves unescaped.
  if AUser <> '' then
  begin
    AConn.Params.Values['User_Name'] := AUser;
    AConn.Params.Values['Password']  := APassword;
  end
  else
    oParams.OSAuthent := True;

  // MSSQLX-specific, consumed by ApplySessionProfile.
  oParams.IsolationLevel := ilReadCommitted;
  oParams.LockTimeout    := 10000;

  AConn.LoginPrompt := False;
end;

/// <summary>
///   Reads the session profile back off the server. Don't trust that the SET
///   statements ran -- ask SQL Server what it thinks.
/// </summary>
procedure VerifySessionProfile(AConn: TFDConnection);
var
  iArithAbort, iAnsiNulls, iQuotedId: Integer;
  oQry: TFDQuery;
begin
  oQry := TFDQuery.Create(nil);
  try
    oQry.Connection := AConn;
    oQry.SQL.Text :=
      'SELECT CAST(SESSIONPROPERTY(''ARITHABORT'')        AS int) AS ArithAbort,' +
      '       CAST(SESSIONPROPERTY(''ANSI_NULLS'')        AS int) AS AnsiNulls,' +
      '       CAST(SESSIONPROPERTY(''QUOTED_IDENTIFIER'') AS int) AS QuotedId';
    oQry.Open;

    iArithAbort := oQry.FieldByName('ArithAbort').AsInteger;
    iAnsiNulls  := oQry.FieldByName('AnsiNulls').AsInteger;
    iQuotedId   := oQry.FieldByName('QuotedId').AsInteger;

    Report('      ARITHABORT=%d  ANSI_NULLS=%d  QUOTED_IDENTIFIER=%d',
      [iArithAbort, iAnsiNulls, iQuotedId]);

    if iArithAbort <> 1 then
      raise Exception.Create(
        'Session profile was not applied: ARITHABORT is OFF.');

    Report('[3/4] Session profile verified on the server.', []);
  finally
    oQry.Free;
  end;
end;

/// <summary>
///   Renders a string as its UTF-16 code units in hex. The console codepage
///   mangles anything non-ASCII on the way out, so echoing the probe value
///   raw proves nothing and makes a mismatch unreadable. Hex survives.
/// </summary>
function HexUnits(const AValue: String): String;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(AValue) do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + IntToHex(Ord(AValue[i]), 4);
  end;
end;

/// <summary>
///   Exercises parameter binding, fetching and Unicode round-trip, and
///   confirms the session actually landed on the requested database.
/// </summary>
procedure VerifyQuery(AConn: TFDConnection; const ADatabase: String);
var
  oQry: TFDQuery;
  sVer, sProbe, sBack, sDb: String;
begin
  oQry := TFDQuery.Create(nil);
  try
    oQry.Connection := AConn;
    oQry.SQL.Text :=
      'SELECT @@VERSION     AS ServerVersion,' +
      '       DB_NAME()     AS CurrentDb,' +
      '       SCHEMA_NAME() AS CurrentSchema,' +
      '       @@SPID        AS Spid,' +
      '       CAST(:probe AS nvarchar(50)) AS UnicodeRoundTrip';
    // U+1F600 as a surrogate pair. Non-BMP characters are where naive nvarchar
    // handling breaks, so it is worth testing on day one.
    sProbe := 'caf' + #$00E9 + ' ' + #$D83D + #$DE00;
    oQry.ParamByName('probe').AsWideString := sProbe;
    oQry.Open;

    // @@VERSION is multi-line; keep the first line.
    sVer := oQry.FieldByName('ServerVersion').AsString;
    sVer := Trim(Copy(sVer, 1, Pos(#10, sVer + #10) - 1));

    sDb := oQry.FieldByName('CurrentDb').AsString;

    Report('      Server : %s', [sVer]);
    Report('      Catalog: %s   Schema: %s   SPID: %d',
      [sDb,
       oQry.FieldByName('CurrentSchema').AsString,
       oQry.FieldByName('Spid').AsInteger]);

    // Ask the server which database it put us in. A connect string that drops
    // DATABASE= still connects -- it just lands on the login's default -- and
    // every remaining check would pass against the wrong catalog. Compared
    // case-insensitively because SQL Server database names follow the
    // instance collation.
    if not SameText(sDb, ADatabase) then
      raise Exception.CreateFmt(
        'Connected to database %s but %s was requested. ' +
        'DATABASE= is missing from the connect string.', [sDb, ADatabase]);
    // Read back as WideString so the comparison itself cannot lose anything.
    // Ordinal compare -- a round-trip that changes case or normalises the
    // surrogate pair is a failure, not a near miss.
    sBack := oQry.FieldByName('UnicodeRoundTrip').AsWideString;
    Report('      Unicode: %s', [HexUnits(sBack)]);

    if sBack <> sProbe then
      raise Exception.CreateFmt(
        'Unicode round-trip altered the value.' + sLineBreak +
        '        sent    : %s' + sLineBreak +
        '        returned: %s',
        [HexUnits(sProbe), HexUnits(sBack)]);

    Report('[4/4] Query and parameter binding OK.', []);
  finally
    oQry.Free;
  end;
end;

procedure Run;
var
  oConn: TFDConnection;
  oLink: TFDPhysMSSQLXDriverLink;
  sServer, sDatabase, sUser, sPassword: String;
begin
  if ParamCount < 2 then
  begin
    Writeln('Usage: MSSQLXDemo <server> <database> [user] [password]');
    Writeln('       omit user/password to use Windows authentication');
    Halt(2);
  end;

  sServer   := ParamStr(1);
  sDatabase := ParamStr(2);
  sUser     := ParamStr(3);
  sPassword := ParamStr(4);

  VerifyDriverRegistered;

  // Not optional, and not merely a design-time convenience. The link is what
  // supplies the ODBC driver name, and TFDPhysODBCDriverBase emits DRIVER=
  // only if it has one. With no link instantiated the connect string carries
  // neither DRIVER= nor DSN=, and the ODBC Driver Manager rejects it with
  // "Data source name not found and no default driver specified".
  //
  // It must exist before the first Open: once the driver is loaded it stops
  // reading the link.
  oLink := TFDPhysMSSQLXDriverLink.Create(nil);
  try
    oConn := TFDConnection.Create(nil);
    try
      Configure(oConn, sServer, sDatabase, sUser, sPassword);

      oConn.Open;
      Report('[2/4] Connected to %s / %s.', [sServer, sDatabase]);

      VerifySessionProfile(oConn);
      VerifyQuery(oConn, sDatabase);

      oConn.Close;
      Writeln;
      Writeln('All checks passed.');
    finally
      oConn.Free;
    end;
  finally
    oLink.Free;
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln;
      Report('%s: %s', [E.ClassName, E.Message]);
      Halt(1);
    end;
  end;
end.
