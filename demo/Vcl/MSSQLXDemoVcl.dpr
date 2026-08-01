program MSSQLXDemoVcl;

uses
  Vcl.Forms,
  Main in 'Main.pas' {Form1},
  SQLXDataModule in 'SQLXDataModule.pas' {DataModule1: TDataModule};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.CreateForm(TDataModule1, DataModule1);
  Application.Run;
end.
