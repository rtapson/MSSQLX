unit SQLXDataModule;

interface

uses
  System.SysUtils, System.Classes, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.VCLUI.Wait,
  FireDAC.Phys.ODBCBase, FireDAC.Phys.MSSQLX, Data.DB,
  FireDAC.Comp.Client, FireDAC.Phys.MSSQLXDef, FireDAC.Stan.Param, FireDAC.DatS,
  FireDAC.DApt.Intf, FireDAC.DApt, FireDAC.Comp.DataSet;

type
  TDataModule1 = class(TDataModule)
    fdconn: TFDConnection;
    FDPhysMSSQLXDriverLink1: TFDPhysMSSQLXDriverLink;
    ProductsQuery: TFDQuery;
    ProductsQueryId: TIntegerField;
    ProductsQueryName: TWideStringField;
    ProductsQueryTypeId: TIntegerField;
    ProductsQueryTypeDetailsId: TIntegerField;
    ProductsQueryManufacturerId: TIntegerField;
    ProductsQueryDateCreated: TSQLTimeStampField;
    ProductsQueryLastUpdate: TSQLTimeStampField;
    ProductsQueryLastupdatedBy: TIntegerField;
    ProductsQueryCategoryId: TIntegerField;
    dsProducts: TDataSource;
    procedure DataModuleCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  DataModule1: TDataModule1;

implementation

{%CLASSGROUP 'Vcl.Controls.TControl'}

{$R *.dfm}

procedure TDataModule1.DataModuleCreate(Sender: TObject);
begin
  fdconn.Open;
end;

end.
