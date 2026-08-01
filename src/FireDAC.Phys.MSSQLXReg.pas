{-------------------------------------------------------------------------------
  FireDAC.Phys.MSSQLXReg -- IDE registration for the MSSQLX driver.

  Kept separate from FireDAC.Phys.MSSQLX so the driver unit itself stays free
  of any design-time dependency and can be linked into a plain console or
  service executable without dragging in the IDE units.

  Registering TFDPhysMSSQLXDriverLink on the palette is the point of the
  design-time package: dropping the link onto a form or data module is what
  supplies the ODBC driver name at design time. Without a link instance the
  connect string carries no DRIVER= and the ODBC Driver Manager rejects it
  with "Data source name not found and no default driver specified".
-------------------------------------------------------------------------------}

unit FireDAC.Phys.MSSQLXReg;

interface

procedure Register;

implementation

uses
  System.Classes,
  FireDAC.Phys.MSSQLX;

procedure Register;
begin
  // 'FireDAC Links' is the page FireDAC's own driver-link components use, so
  // MSSQLX lands next to them rather than in a category of its own.
  RegisterComponents('FireDAC Links', [TFDPhysMSSQLXDriverLink]);
end;

end.
