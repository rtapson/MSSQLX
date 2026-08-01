object DataModule1: TDataModule1
  OnCreate = DataModuleCreate
  Height = 1234
  Width = 2070
  PixelsPerInch = 192
  object fdconn: TFDConnection
    Params.Server = '.'
    Params.OSAuthent = True
    Params.MARS = True
    Params.Encrypt = False
    Params.TrustServerCertificate = False
    Params.ApplicationName = 'TESTAPP'
    Params.LoginTimeout = 0
    Params.LockTimeout = -1
    Params.IsolationLevel = ilUnspecified
    Params.ApplySessionProfile = True
    Params.Strings = (
      'Database=MakerParts'
      'ApplicationName=TESTAPP'
      'OSAuthent=True'
      'MARS=True'
      'Server=.'
      'DriverID=MSSQLX')
    LoginPrompt = False
    Left = 360
    Top = 136
  end
  object FDPhysMSSQLXDriverLink1: TFDPhysMSSQLXDriverLink
    ODBCDriver = 'ODBC Driver 18 for SQL Server'
    Left = 608
    Top = 112
  end
  object ProductsQuery: TFDQuery
    Connection = fdconn
    SQL.Strings = (
      'SELECT * FROM Products')
    Left = 376
    Top = 360
    object ProductsQueryId: TIntegerField
      AutoGenerateValue = arDefault
      FieldName = 'Id'
      Origin = 'Id'
      ProviderFlags = [pfInKey]
      ReadOnly = True
    end
    object ProductsQueryName: TWideStringField
      AutoGenerateValue = arDefault
      FieldName = 'Name'
      Origin = 'Name'
      ProviderFlags = []
      ReadOnly = True
      Size = 50
    end
    object ProductsQueryTypeId: TIntegerField
      AutoGenerateValue = arDefault
      FieldName = 'TypeId'
      Origin = 'TypeId'
      ProviderFlags = []
      ReadOnly = True
    end
    object ProductsQueryTypeDetailsId: TIntegerField
      AutoGenerateValue = arDefault
      FieldName = 'TypeDetailsId'
      Origin = 'TypeDetailsId'
      ProviderFlags = []
      ReadOnly = True
    end
    object ProductsQueryManufacturerId: TIntegerField
      AutoGenerateValue = arDefault
      FieldName = 'ManufacturerId'
      Origin = 'ManufacturerId'
      ProviderFlags = []
      ReadOnly = True
    end
    object ProductsQueryDateCreated: TSQLTimeStampField
      AutoGenerateValue = arDefault
      FieldName = 'DateCreated'
      Origin = 'DateCreated'
      ProviderFlags = []
      ReadOnly = True
    end
    object ProductsQueryLastUpdate: TSQLTimeStampField
      AutoGenerateValue = arDefault
      FieldName = 'LastUpdate'
      Origin = 'LastUpdate'
      ProviderFlags = []
      ReadOnly = True
    end
    object ProductsQueryLastupdatedBy: TIntegerField
      AutoGenerateValue = arDefault
      FieldName = 'LastupdatedBy'
      Origin = 'LastupdatedBy'
      ProviderFlags = []
      ReadOnly = True
    end
    object ProductsQueryCategoryId: TIntegerField
      AutoGenerateValue = arDefault
      FieldName = 'CategoryId'
      Origin = 'CategoryId'
      ProviderFlags = []
      ReadOnly = True
    end
  end
  object dsProducts: TDataSource
    DataSet = ProductsQuery
    Left = 576
    Top = 352
  end
end
