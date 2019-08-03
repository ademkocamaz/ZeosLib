{*********************************************************}
{                                                         }
{                 Zeos Database Objects                   }
{         Interbase Database Connectivity Classes         }
{                                                         }
{        Originally written by Sergey Merkuriev           }
{                                                         }
{*********************************************************}

{@********************************************************}
{    Copyright (c) 1999-2012 Zeos Development Group       }
{                                                         }
{ License Agreement:                                      }
{                                                         }
{ This library is distributed in the hope that it will be }
{ useful, but WITHOUT ANY WARRANTY; without even the      }
{ implied warranty of MERCHANTABILITY or FITNESS FOR      }
{ A PARTICULAR PURPOSE.  See the GNU Lesser General       }
{ Public License for more details.                        }
{                                                         }
{ The source code of the ZEOS Libraries and packages are  }
{ distributed under the Library GNU General Public        }
{ License (see the file COPYING / COPYING.ZEOS)           }
{ with the following  modification:                       }
{ As a special exception, the copyright holders of this   }
{ library give you permission to link this library with   }
{ independent modules to produce an executable,           }
{ regardless of the license terms of these independent    }
{ modules, and to copy and distribute the resulting       }
{ executable under terms of your choice, provided that    }
{ you also meet, for each linked independent module,      }
{ the terms and conditions of the license of that module. }
{ An independent module is a module which is not derived  }
{ from or based on this library. If you modify this       }
{ library, you may extend this exception to your version  }
{ of the library, but you are not obligated to do so.     }
{ If you do not wish to do so, delete this exception      }
{ statement from your version.                            }
{                                                         }
{                                                         }
{ The project web site is located on:                     }
{   http://zeos.firmos.at  (FORUM)                        }
{   http://sourceforge.net/p/zeoslib/tickets/ (BUGTRACKER)}
{   svn://svn.code.sf.net/p/zeoslib/code-0/trunk (SVN)    }
{                                                         }
{   http://www.sourceforge.net/projects/zeoslib.          }
{                                                         }
{                                                         }
{                                 Zeos Development Group. }
{********************************************************@}

unit ZDbcInterbase6;

interface

{$I ZDbc.inc}

{$IFNDEF ZEOS_DISABLE_INTERBASE} //if set we have an empty unit
uses
  Classes, {$IFDEF MSEgui}mclasses,{$ENDIF} SysUtils,
  {$IFNDEF NO_UNIT_CONTNRS}Contnrs,{$ENDIF}
  {$IF defined(OLDFPC) or defined(NO_UNIT_CONTNRS)}ZClasses,{$IFEND}
  ZPlainFirebirdDriver, ZCompatibility, ZDbcUtils, ZDbcIntfs,
  ZDbcConnection, ZPlainFirebirdInterbaseConstants, ZSysUtils, ZDbcLogging,
  ZDbcInterbase6Utils, ZDbcGenericResolver, ZTokenizer, ZGenericSqlAnalyser,
  ZURL;

type

  {** Implements Interbase6 Database Driver. }
  TZInterbase6Driver = class(TZAbstractDriver)
  public
    constructor Create; override;
    function Connect(const Url: TZURL): IZConnection; override;
    function GetMajorVersion: Integer; override;
    function GetMinorVersion: Integer; override;

    function GetTokenizer: IZTokenizer; override;
    function GetStatementAnalyser: IZStatementAnalyser; override;
  end;

  {** Represents a Interbase specific connection interface. }
  IZInterbase6Connection = interface (IZConnection)
    ['{E870E4FE-21EB-4725-B5D8-38B8A2B12D0B}']
    function GetDBHandle: PISC_DB_HANDLE;
    function GetTrHandle: PISC_TR_HANDLE;
    function GetDialect: Word;
    function GetPlainDriver: IZInterbasePlainDriver;
    function GetXSQLDAMaxSize: LongWord;
  end;

  TZInterbase6Connection = class;
  TZIBTransactionManager = class;

  TOnCursorClose = procedure(const RS: IZResultSet) of object;

  TZIBTransaction = class(TZCodePagedObject, IImmediatelyReleasable)
  private
    fDoCommit, fDoLog: Boolean;
    FOpenCursors: TList;
    FTrHandle: TISC_TR_HANDLE;
    {$IFDEF AUTOREFCOUNT}[weak]{$ENDIF}FOwner: TZIBTransactionManager;
  public
    procedure Commit;
    procedure Rollback;
    procedure RegisterOpenCursor(const RS: IZResultSet; Out OnCursorClose: TOnCursorClose);
    procedure DeRegisterOpenCursor(const RS: IZResultSet);
    procedure ReleaseImmediat(const Sender: IImmediatelyReleasable; var AError: EZSQLConnectionLost);
    procedure StartTransaction;
    function GetTrHandle: PISC_TR_HANDLE;
  public
    constructor Create(const Owner: TZIBTransactionManager);
    procedure BeforeDestruction; override;
  end;


  TZIBTransactionManager = class(TZCodePagedObject, IImmediatelyReleasable)
  private
    {$IFDEF AUTOREFCOUNT}[weak]{$ENDIF}FOwner: TZInterbase6Connection;
    FOrphanTransactions, FTransactions: TObjectList;
  public
    function GetTrHandle: PISC_TR_HANDLE;
    procedure RemoveOrphan(const Obj: TZIBTransaction);
    procedure AddToOrphanList(const Obj: TZIBTransaction);
    procedure ReleaseImmediat(const Sender: IImmediatelyReleasable; var AError: EZSQLConnectionLost);
    function GetActiveTransaction: TZIBTransaction;
  public
    function StartTransaction(TransactIsolationLevel: TZTransactIsolationLevel;
      AutoCommit, ReadOnly: Boolean): Integer; overload;
    function StartTransaction: Integer; overload;
    function Commit: Integer;
    function Rollback: Integer;
  public
    Constructor Create(Owner: TZInterbase6Connection);
  end;

  {** Implements Interbase6 Database Connection. }

  { TZInterbase6Connection }

  TZInterbase6Connection = class(TZAbstractConnection, IZInterbase6Connection)
  private
    FDialect: Word;
    FHandle: TISC_DB_HANDLE;
    FTrHandle: TISC_TR_HANDLE;
    FStatusVector: TARRAY_ISC_STATUS;
    FHardCommit: boolean;
    FHostVersion: Integer;
    FClientVersion: Integer;
    FIsFirebirdLib: Boolean; // never use this directly, always use IsFirbirdLib
    FIsInterbaseLib: Boolean; // never use this directly, always use IsInterbaseLib
    FXSQLDAMaxSize: LongWord;
    FPlainDriver: IZInterbasePlainDriver;
    FTPBs: array[Boolean,TZTransactIsolationLevel] of RawByteString;
    FTEBs: array[Boolean,TZTransactIsolationLevel] of TISC_TEB;
    procedure CloseTransaction;
    procedure DetermineClientTypeAndVersion;
    procedure AssignISC_Parameters;
  protected
    procedure InternalCreate; override;
    procedure OnPropertiesChange({%H-}Sender: TObject); override;
  public
    procedure StartTransaction;
    function GetHostVersion: Integer; override;
    function GetClientVersion: Integer; Override;
    function IsFirebirdLib: Boolean;
    function IsInterbaseLib: Boolean;
    function GetDBHandle: PISC_DB_HANDLE;
    function GetTrHandle: PISC_TR_HANDLE;
    function GetDialect: Word;
    function GetXSQLDAMaxSize: LongWord;
    procedure CreateNewDatabase(const SQL: RawByteString);
  public
    function CreateRegularStatement(Info: TStrings): IZStatement; override;
    function CreatePreparedStatement(const SQL: string; Info: TStrings):
      IZPreparedStatement; override;
    function CreateCallableStatement(const SQL: string; Info: TStrings):
      IZCallableStatement; override;

    function CreateSequence(const Sequence: string; BlockSize: Integer):
      IZSequence; override;

    procedure SetTransactionIsolation(Level: TZTransactIsolationLevel); override;
    procedure SetReadOnly(Value: Boolean); override;
    procedure SetAutoCommit(Value: Boolean); override;

    procedure Commit; override;
    procedure Rollback; override;

    function PingServer: Integer; override;

    function ConstructConnectionString: String;
    procedure Open; override;
    procedure InternalClose; override;

    function GetBinaryEscapeString(const Value: RawByteString): String; override;
    function GetBinaryEscapeString(const Value: TBytes): String; override;
  end;

  {** Implements a specialized cached resolver for Interbase/Firebird. }
  TZInterbase6CachedResolver = class(TZGenericCachedResolver)
  public
    function FormCalculateStatement(Columns: TObjectList): string; override;
  end;

  {** Implements a Interbase 6 sequence. }
  TZInterbase6Sequence = class(TZAbstractSequence)
  public
    function GetCurrentValue: Int64; override;
    function GetNextValue: Int64; override;
    function GetCurrentValueSQL: string; override;
    function GetNextValueSQL: string; override;
  end;


var
  {** The common driver manager object. }
  Interbase6Driver: IZDriver;

{$ENDIF ZEOS_DISABLE_INTERBASE} //if set we have an empty unit
implementation
{$IFNDEF ZEOS_DISABLE_INTERBASE} //if set we have an empty unit

uses ZFastCode, ZDbcInterbase6Statement, ZDbcInterbase6Metadata, ZEncoding,
  ZInterbaseToken, ZInterbaseAnalyser, ZDbcMetadata, ZMessages, Math
  {$IF not defined(NO_UNIT_CONTNRS) and not defined(OLDFPC)},ZClasses{$IFEND}
  {$IFDEF WITH_UNITANSISTRINGS}, AnsiStrings{$ENDIF};

{ TZInterbase6Driver }

{**
  Attempts to make a database connection to the given URL.
  The driver should return "null" if it realizes it is the wrong kind
  of driver to connect to the given URL.  This will be common, as when
  the JDBC driver manager is asked to connect to a given URL it passes
  the URL to each loaded driver in turn.

  <P>The driver should raise a SQLException if it is the right
  driver to connect to the given URL, but has trouble connecting to
  the database.

  <P>The java.util.Properties argument can be used to passed arbitrary
  string tag/value pairs as connection arguments.
  Normally at least "user" and "password" properties should be
  included in the Properties.

  @param url the URL of the database to which to connect
  @param info a list of arbitrary string tag/value pairs as
    connection arguments. Normally at least a "user" and
    "password" property should be included.
  @return a <code>Connection</code> object that represents a
    connection to the URL
}
function TZInterbase6Driver.Connect(const Url: TZURL): IZConnection;
begin
  Result := TZInterbase6Connection.Create(Url);
end;

{**
  Constructs this object with default properties.
}
constructor TZInterbase6Driver.Create;
begin
  inherited Create;
  AddSupportedProtocol(AddPlainDriverToCache(TZInterbase6PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird10PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird15PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird20PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird21PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird25PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird30PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird30PlainDriver.Create, 'firebird'));
  AddSupportedProtocol(AddPlainDriverToCache(TZInterbase6PlainDriver.Create, 'interbase'));
  // embedded drivers
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebirdD15PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebirdD20PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebirdD21PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebirdD25PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebirdD30PlainDriver.Create));
end;

{**
  Gets the driver's major version number. Initially this should be 1.
  @return this driver's major version number
}
function TZInterbase6Driver.GetMajorVersion: Integer;
begin
  Result := 1;
end;

{**
  Gets the driver's minor version number. Initially this should be 0.
  @return this driver's minor version number
}
function TZInterbase6Driver.GetMinorVersion: Integer;
begin
  Result := 0;
end;

{**
  Gets a SQL syntax tokenizer.
  @returns a SQL syntax tokenizer object.
}
function TZInterbase6Driver.GetTokenizer: IZTokenizer;
begin
  Result := TZInterbaseTokenizer.Create;
end;

{**
  Creates a statement analyser object.
  @returns a statement analyser object.
}
function TZInterbase6Driver.GetStatementAnalyser: IZStatementAnalyser;
begin
  Result := TZInterbaseStatementAnalyser.Create; { thread save! Allways return a new Analyser! }
end;

{ TZInterbase6Connection }

procedure TZInterbase6Connection.AssignISC_Parameters;
var
  RoleName: string;
  ConnectTimeout : integer;
  WireCompression: Boolean;
begin
  { set default sql dialect it can be overriden }
  FDialect := StrToIntDef(Info.Values['dialect'], SQL_DIALECT_CURRENT);

  Info.BeginUpdate; // Do not call OnPropertiesChange every time a property changes
  { Processes connection properties. }
  if Info.Values['isc_dpb_username'] = '' then
    Info.Values['isc_dpb_username'] := Url.UserName;
  if Info.Values['isc_dpb_password'] = '' then
    Info.Values['isc_dpb_password'] := Url.Password;

  if FClientCodePage = '' then //was set on inherited Create(...)
    if Info.Values['isc_dpb_lc_ctype'] <> '' then //Check if Dev set's it manually
    begin
      FClientCodePage := Info.Values['isc_dpb_lc_ctype'];
      CheckCharEncoding(FClientCodePage, True);
    end;
  Info.Values['isc_dpb_lc_ctype'] := FClientCodePage;

  RoleName := Trim(Info.Values['rolename']);
  if RoleName <> '' then
    Info.Values['isc_dpb_sql_role_name'] := UpperCase(RoleName);

  ConnectTimeout := StrToIntDef(Info.Values['timeout'], -1);
  if ConnectTimeout >= 0 then
    Info.Values['isc_dpb_connect_timeout'] := ZFastCode.IntToStr(ConnectTimeout);

  WireCompression := StrToBoolEx(Info.Values['wirecompression']);
  if WireCompression then
    Info.Values['isc_dpb_config'] :=
      Info.Values['isc_dpb_config'] + LineEnding + 'WireCompression=true';

  if Info.IndexOf('isc_dpb_sql_dialect') = -1 then
    Info.Values['isc_dpb_sql_dialect'] := IntToStr(FDialect);

  if (GetClientVersion >= 2005000) and IsFirebirdLib then begin
    if (Info.IndexOf('isc_dpb_utf8_filename') = -1) and ((FClientCodePage = 'UTF8') or (FClientCodePage = 'UNICODE_FSS')) then
      Info.Add('isc_dpb_utf8_filename');
  end else
    if (Info.IndexOf('isc_dpb_utf8_filename') <> -1) then
      Info.Delete(Info.IndexOf('isc_dpb_utf8_filename'));
  Info.EndUpdate;
end;

procedure TZInterbase6Connection.CloseTransaction;
begin
  if FTrHandle <> 0 then begin
    if AutoCommit then begin
      GetPlainDriver.isc_commit_transaction(@FStatusVector, @FTrHandle);
      DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol,
        'COMMIT TRANSACTION "'+ConSettings^.DataBase+'"');
    end else begin
      GetPlainDriver.isc_rollback_transaction(@FStatusVector, @FTrHandle);
      DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol,
        'ROLLBACK TRANSACTION "'+ConSettings^.DataBase+'"');
    end;
    FTrHandle := 0;
    CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcDisconnect);
  end;
end;

{**
  Releases a Connection's database and JDBC resources
  immediately instead of waiting for
  them to be automatically released.

  <P><B>Note:</B> A Connection is automatically closed when it is
  garbage collected. Certain fatal errors also result in a closed
  Connection.
}
procedure TZInterbase6Connection.InternalClose;
begin
  CloseTransaction;
  if Assigned(DriverManager) and DriverManager.HasLoggingListener then
    DriverManager.LogMessage(lcConnect, ConSettings^.Protocol,
        'DISCONNECT FROM "'+ConSettings^.DataBase+'"');
  if FHandle <> 0 then begin
    GetPlainDriver.isc_detach_database(@FStatusVector, @FHandle);
    FHandle := 0;
    CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcDisconnect);
  end;
end;

{**
   Commit current transaction
}
procedure TZInterbase6Connection.Commit;
begin
  if Closed then
    Exit;
  if GetAutoCommit
  then raise EZSQLException.Create(SInvalidOpInAutoCommit);
  if (FTrHandle <> 0) then
    if FHardCommit then begin
      if GetPlainDriver.isc_commit_transaction(@FStatusVector, @FTrHandle) <> 0 then
      // Jan Baumgarten: Added error checking here because setting the transaction
      // handle to 0 before we have checked for an error is simply wrong.
      CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcTransaction);
      FTrHandle := 0; //normaly not required! Old server code?
    end else
      if GetPlainDriver.isc_commit_retaining(@FStatusVector, @FTrHandle) <> 0 then
        CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcTransaction);
  if DriverManager.HasLoggingListener then
    DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol, 'TRANSACTION COMMIT');
end;

{**
  Constructs this object and assignes the main properties.
}
procedure TZInterbase6Connection.InternalCreate;
begin
  FClientVersion := -1;
  FIsFirebirdLib := false;
  FIsInterbaseLib := false;

  FMetadata := TZInterbase6DatabaseMetadata.Create(Self, Url);

  { set default sql dialect it can be overriden }
  FDialect := StrToIntDef(Info.Values['dialect'], SQL_DIALECT_CURRENT);

  FHardCommit := StrToBoolEx(Info.Values['hard_commit']);

  FXSQLDAMaxSize := 64*1024; //64KB by default
  FHandle := 0;
end;

procedure TZInterbase6Connection.OnPropertiesChange(Sender: TObject);
var
  B: Boolean;
  TIL: TZTransactIsolationLevel;
begin
  if StrToBoolEx(Info.Values['hard_commit']) <> FHardCommit then begin
    CloseTransaction;
    FHardCommit := StrToBoolEx(Info.Values['hard_commit']);
  end;
  for b := false to true do
    for til := low(TZTransactIsolationLevel) to high(TZTransactIsolationLevel) do begin
      FTPBs[b][TIL] := '';
      FTEBs[b][TIL].tpb_length := 0;
      FTEBs[b][TIL].tpb_address := nil;
    end;
end;

{**
  Creates a <code>Statement</code> object for sending
  SQL statements to the database.
  SQL statements without parameters are normally
  executed using Statement objects. If the same SQL statement
  is executed many times, it is more efficient to use a
  <code>PreparedStatement</code> object.
  <P>
  Result sets created using the returned <code>Statement</code>
  object will by default have forward-only type and read-only concurrency.

  @param Info a statement parameters.
  @return a new Statement object
}
function TZInterbase6Connection.CreateRegularStatement(Info: TStrings):
  IZStatement;
begin
  if IsClosed then
    Open;
  Result := TZInterbase6Statement.Create(Self, Info);
end;

{**
  Gets the host's full version number. Initially this should be 0.
  The format of the version returned must be XYYYZZZ where
   X   = Major version
   YYY = Minor version
   ZZZ = Sub version
  @return this server's full version number
}
function TZInterbase6Connection.GetHostVersion: Integer;
begin
  Result := FHostVersion;
end;

{**
  Determines the Client Library vendor and version. Works for Firebird 1.5+ and
  Interbase 7+
}
procedure TZInterbase6Connection.DetermineClientTypeAndVersion;
var
  Major, Minor, Release: Integer;
  VersionStr: String;
  FbPos: Integer;
  DotPos: Integer;
begin
  Release := 0;

  VersionStr := GetPlainDriver.isc_get_client_version;
  FbPos := System.Pos('firebird', LowerCase(VersionStr));
  if FbPos > 0 then begin
    FIsFirebirdLib := true;
    // remove the fake Major version number
    DotPos := System.Pos('.', VersionStr);
    Delete(VersionStr, 1, DotPos);
    // remove the fake Minor version number
    DotPos := System.Pos('.', VersionStr);
    Delete(VersionStr, 1, DotPos);
    // get the release number
    DotPos := System.Pos('.', VersionStr);
    Release := StrToIntDef(Copy(VersionStr, 1, DotPos - 1), 0);
    // remove the Firebird brand including the space
    FbPos := System.Pos('firebird', LowerCase(VersionStr));
    Delete(VersionStr, 1, FbPos + 8);
    // get the major and minor version numbers
    DotPos := System.Pos('.', VersionStr);
    Major := StrToIntDef(Copy(VersionStr, 1, DotPos - 1), 0);
    Minor := StrToIntDef(Copy(VersionStr, DotPos + 1, length(VersionStr)), 0);
  end else begin
    Major := FPlainDriver.isc_get_client_major_version();
    Minor := FPlainDriver.isc_get_client_minor_version();
    FIsInterbaseLib := Major <> 0;
  end;

  FClientVersion := Major * 1000000 + Minor * 1000 + Release;
end;

{**
  Gets the client's full version number. Initially this should be 0.
  The format of the version returned must be XYYYZZZ where
   X   = Major version
   YYY = Minor version
   ZZZ = Sub version
  @return this clients's full version number
}
function TZInterbase6Connection.GetClientVersion: Integer;
begin
  if FClientVersion = -1 then DetermineClientTypeAndVersion;
  Result := FClientVersion;
end;

{**
  Determines wether the client library is Firebird. Works for Firebird 1.5+
  Note that this Function cannot reliably determine wether you are on interbase.
  Use IsInterbaseLib for that.
}
function TZInterbase6Connection.IsFirebirdLib: Boolean;
begin
  if FClientVersion = -1 then DetermineClientTypeAndVersion;
  Result := FIsFirebirdLib;
end;

{**
  Determines wether the client library is Firebird. Works for Interbase 7.0+
  Note that this Function cannot reliably determine wether you are on interbase.
  Use IsInterbaseLib for that.
}
function TZInterbase6Connection.IsInterbaseLib: Boolean;
begin
  if FClientVersion = -1 then DetermineClientTypeAndVersion;
  Result := FIsInterbaseLib;
end;

{**
   Get database connection handle.
   @return database handle
}
function TZInterbase6Connection.GetDBHandle: PISC_DB_HANDLE;
begin
  Result := @FHandle;
end;

{**
   Return Interbase dialect number. Dialect a dialect Interbase SQL
   must be 1 or 2 or 3.
   @return dialect number
}
function TZInterbase6Connection.GetDialect: Word;
begin
  Result := FDialect;
end;

function TZInterbase6Connection.GetXSQLDAMaxSize: LongWord;
begin
  Result := FXSQLDAMaxSize;
end;

{**
   Return native interbase plain driver
   @return plain driver
}
function TZInterbase6Connection.GetPlainDriver: IZInterbasePlainDriver;
begin
  if FPlainDriver = nil then
    FPlainDriver := PlainDriver as IZInterbasePlainDriver;
  Result := FPlainDriver;
end;

{**
   Get Interbase transaction handle
   @return transaction handle
}
function TZInterbase6Connection.GetTrHandle: PISC_TR_HANDLE;
begin
  if (FTrHandle = 0) and not Closed then
    StartTransaction;
  Result := @FTrHandle;
end;

{**
  Constructs the connection string for the current connection
}
function TZInterbase6Connection.ConstructConnectionString: String;
var
  Protocol: String;
  ConnectionString: String;
begin
  Protocol := LowerCase(Info.Values['fb_protocol']);

  if ((Protocol = 'inet') or (Protocol = 'wnet') or (Protocol = 'xnet') or (Protocol = 'local')) and IsFirebirdLib then begin
    if GetClientVersion >= 3000000 then begin
      if protocol = 'inet' then begin
        if Port <> 0
        then ConnectionString := 'inet://' + HostName + ':' + ZFastCode.IntToStr(Port) + '/' + Database
        else ConnectionString := 'inet://' + HostName + '/' + Database;
      end else if Protocol = 'wnet' then begin
        if HostName <> ''
        then ConnectionString := 'wnet://' + HostName + '/' + Database
        else ConnectionString := 'wnet://' + Database
      end else if Protocol = 'xnet' then begin
        ConnectionString := 'xnet://' + Database;
      end else begin
        ConnectionString := Database;
      end;
    end else begin
      if protocol = 'inet' then begin
        if HostName = ''
        then ConnectionString := 'localhost'
        else ConnectionString := HostName;
        if Port <> 0 then begin
          ConnectionString := ConnectionString + '/' + ZFastCode.IntToStr(Port);
        end;
        ConnectionString := ConnectionString + ':';
        ConnectionString := ConnectionString + Database;
      end else if Protocol = 'wnet' then begin
        if HostName = ''
        then ConnectionString := '\\localhost'
        else ConnectionString := '\\' + HostName;
        if Port <> 0 then begin
          ConnectionString := ConnectionString + '@' + ZFastCode.IntToStr(Port);
        end;
        ConnectionString := ConnectionString + '\' + Database;
      end else begin
        ConnectionString := Database;
      end;
    end;
  end else begin
    if HostName <> '' then
      if Port <> 0 then
        ConnectionString := HostName + '/' + ZFastCode.IntToStr(Port) + ':' + Database
      else
        ConnectionString := HostName + ':' + Database
    else
      ConnectionString := Database;
  end;

  Result := ConnectionString;
end;

{**
  Opens a connection to database server with specified parameters.
}
procedure TZInterbase6Connection.Open;
const sCS_NONE = 'NONE';
var
  DPB: RawByteString;
  DBName: array[0..512] of AnsiChar;
  NewDB: RawByteString;
  ConnectionString: String;
  procedure PrepareDPB;
  var
    R: RawByteString;
    P: PAnsiChar;
    L: LengthInt;
  begin
    if (Info.IndexOf('isc_dpb_utf8_filename') = -1) then begin
      R := ConSettings^.ConvFuncs.ZStringToRaw(ConnectionString, ConSettings^.CTRL_CP, ZOSCodePage);
      DPB := GenerateDPB(FPlainDriver, Info, ConSettings, ZOSCodePage);
    end else begin
      R := ConSettings^.ConvFuncs.ZStringToRaw(ConnectionString, ConSettings^.CTRL_CP, zCP_UTF8);
      DPB := GenerateDPB(FPlainDriver, Info, ConSettings, zCP_UTF8);
    end;
    P := Pointer(R);
    L := Min(SizeOf(DBName)-1, Length(R){$IFDEF WITH_TBYTES_AS_RAWBYTESTRING}-1{$ENDIF});
    if P <> nil then
      Move(P^, DBName[0], L);
    AnsiChar((PAnsiChar(@DBName[0])+L)^) := AnsiChar(#0);
  end;
begin
  if not Closed then
    Exit;

  if TransactIsolationLevel = tiReadUncommitted then
    raise EZSQLException.Create('Isolation level do not capable');
  if ConSettings^.ClientCodePage = nil then
    CheckCharEncoding(FClientCodePage, True);

  AssignISC_Parameters;
  ConnectionString := ConstructConnectionString;

  { Create new db if needed }
  if Info.Values['createNewDatabase'] <> '' then begin
    if (GetClientVersion >= 2005000) and IsFirebirdLib then begin
      if (Info.Values['isc_dpb_lc_ctype'] <> '') and (Info.Values['isc_dpb_set_db_charset'] = '') then
        Info.Values['isc_dpb_set_db_charset'] := Info.Values['isc_dpb_lc_ctype'];
      PrepareDPB;
      if GetPlainDriver.isc_create_database(@FStatusVector, SmallInt(StrLen(@DBName[0])),
          @DBName[0], @FHandle, Smallint(Length(DPB)),Pointer(DPB), 0) <> 0 then
        CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcConnect);
    end else begin
      NewDB := ConSettings^.ConvFuncs.ZStringToRaw(Info.Values['createNewDatabase'],
        ConSettings^.CTRL_CP, zOSCodePage);
      CreateNewDatabase(NewDB);
      { Logging connection action }
      DriverManager.LogMessage(lcConnect, ConSettings^.Protocol,
        'CREATE DATABASE "'+NewDB+'" AS USER "'+ ConSettings^.User+'"');
      Info.Values['createNewDatabase'] := '';
      FHandle := 0;
    end;
  end;
  if FHandle = 0 then begin
    PrepareDPB;
    { Connect to Interbase6 database. }
    GetPlainDriver.isc_attach_database(@FStatusVector,
      ZFastCode.StrLen(@DBName[0]), @DBName[0],
      @FHandle, Length(DPB), Pointer(DPB));

    { Check connection error }
    CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcConnect);

    { Dialect could have changed by isc_dpb_set_db_SQL_dialect command }
    FDialect := GetDBSQLDialect(GetPlainDriver, @FHandle, ConSettings);
    { Logging connection action }
    DriverManager.LogMessage(lcConnect, ConSettings^.Protocol,
      'CONNECT TO "'+ConSettings^.DataBase+'" AS USER "'+ConSettings^.User+'"');
  end;

  FHardCommit := StrToBoolEx(Info.Values['hard_commit']);
  { Start transaction }
  if not FHardCommit then
    StartTransaction;

  inherited Open;

  with GetMetadata.GetDatabaseInfo as IZInterbaseDatabaseInfo do
  begin
    CollectServerInformations; //keep this one first!
    FHostVersion := GetHostVersion;
    FXSQLDAMaxSize := GetMaxSQLDASize;
  end;

  {Check for ClientCodePage: if empty switch to database-defaults
    and/or check for charset 'NONE' which has a different byte-width
    and no conversations where done except the collumns using collations}
  with GetMetadata.GetCollationAndCharSet('', '', '', '') do
  begin
    if Next then
      if FCLientCodePage = '' then
      begin
        FCLientCodePage := GetString(CollationAndCharSetNameIndex);
        if Info.Values['ResetCodePage'] <> '' then
        begin
          ConSettings^.ClientCodePage := FPlainDriver.ValidateCharEncoding(FClientCodePage);
          ResetCurrentClientCodePage(Info.Values['ResetCodePage']);
        end
        else
          CheckCharEncoding(FClientCodePage);
      end
      else
        if GetString(CollationAndCharSetNameIndex) = sCS_NONE then
        begin
          if not ( FClientCodePage = sCS_NONE ) then
          begin
            Info.Values['isc_dpb_lc_ctype'] := sCS_NONE;
            {save the user wanted CodePage-Informations}
            Info.Values['ResetCodePage'] := FClientCodePage;
            FClientCodePage := sCS_NONE;
            { charset 'NONE' can't convert anything and write 'Data as is'!
              If another charset was set on attaching the Server then all
              column collations are retrieved with newly choosen collation.
              BUT NO string convertations where done! So we need a
              reopen (since we can set the Client-CharacterSet only on
              connecting) to determine charset 'NONE' corectly. Then the column
              collations have there proper CharsetID's to encode all strings
              correctly. }
            Self.Close;
            Self.Open;
            { Create a new PZCodePage for the new environment-variables }
          end
          else
          begin
            if Info.Values['ResetCodePage'] <> '' then
            begin
              ConSettings^.ClientCodePage := FPlainDriver.ValidateCharEncoding(sCS_NONE);
              ResetCurrentClientCodePage(Info.Values['ResetCodePage']);
            end
            else
              CheckCharEncoding(sCS_NONE);
          end;
        end
        else
          if Info.Values['ResetCodePage'] <> '' then
            ResetCurrentClientCodePage(Info.Values['ResetCodePage']);
    Close;
  end;
  if FClientCodePage = sCS_NONE then
    ConSettings.AutoEncode := True; //Must be set!
end;

{**
  Creates a <code>PreparedStatement</code> object for sending
  parameterized SQL statements to the database.

  A SQL statement with or without IN parameters can be
  pre-compiled and stored in a PreparedStatement object. This
  object can then be used to efficiently execute this statement
  multiple times.

  <P><B>Note:</B> This method is optimized for handling
  parametric SQL statements that benefit from precompilation. If
  the driver supports precompilation,
  the method <code>prepareStatement</code> will send
  the statement to the database for precompilation. Some drivers
  may not support precompilation. In this case, the statement may
  not be sent to the database until the <code>PreparedStatement</code> is
  executed.  This has no direct effect on users; however, it does
  affect which method throws certain SQLExceptions.

  Result sets created using the returned PreparedStatement will have
  forward-only type and read-only concurrency, by default.

  @param sql a SQL statement that may contain one or more '?' IN
    parameter placeholders
  @return a new PreparedStatement object containing the
    pre-compiled statement
}
function TZInterbase6Connection.CreatePreparedStatement(
  const SQL: string; Info: TStrings): IZPreparedStatement;
begin
  if IsClosed then
    Open;
  Result := TZInterbase6PreparedStatement.Create(Self, SQL, Info);
end;

{**
  Creates a <code>CallableStatement</code> object for calling
  database stored procedures.
  The <code>CallableStatement</code> object provides
  methods for setting up its IN and OUT parameters, and
  methods for executing the call to a stored procedure.

  <P><B>Note:</B> This method is optimized for handling stored
  procedure call statements. Some drivers may send the call
  statement to the database when the method <code>prepareCall</code>
  is done; others
  may wait until the <code>CallableStatement</code> object
  is executed. This has no
  direct effect on users; however, it does affect which method
  throws certain SQLExceptions.

  Result sets created using the returned CallableStatement will have
  forward-only type and read-only concurrency, by default.

  @param sql a SQL statement that may contain one or more '?'
    parameter placeholders. Typically this  statement is a JDBC
    function call escape string.
  @param Info a statement parameters.
  @return a new CallableStatement object containing the
    pre-compiled SQL statement
}
function TZInterbase6Connection.CreateCallableStatement(const SQL: string;
  Info: TStrings): IZCallableStatement;
begin
  if IsClosed then
    Open;
  Result := TZInterbase6CallableStatement.Create(Self, SQL, Info);
end;

{**
  Drops all changes made since the previous
  commit/rollback and releases any database locks currently held
  by this Connection. This method should be used only when auto-
  commit has been disabled.
  @see #setAutoCommit
}
procedure TZInterbase6Connection.Rollback;
begin
  if Closed then
    Exit;
  if GetAutoCommit
  then raise EZSQLException.Create(cSInvalidOpInAutoCommit);
  if FTrHandle <> 0 then begin
    if FHardCommit then begin
      GetPlainDriver.isc_rollback_transaction(@FStatusVector, @FTrHandle);
      CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings);
      DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol, 'TRANSACTION ROLLBACK');
      FTrHandle := 0; //that's done by fb, obsolete code?
    end else begin
      GetPlainDriver.isc_rollback_retaining(@FStatusVector, @FTrHandle);
      CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings);
      DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol, 'TRANSACTION ROLLBACK');
  end;
  end;
end;

{**
  Checks if a connection is still alive by doing a call to isc_database_info
  It does not matter what info we request, we are not looking at it, as long
  as it is something which should _always_ work if the connection is there.
  We check if the error returned is one of the net_* errors described in the
  firebird client documentation (isc_network_error .. isc_net_write_err).
  Returns 0 if the connection is OK
  Returns non zero if the connection is not OK
}
function TZInterbase6Connection.PingServer: integer;
var
  DatabaseInfoCommand: Char;
  Buffer: array[0..IBBigLocalBufferLength - 1] of AnsiChar;
  ErrorCode: ISC_STATUS;
begin
  DatabaseInfoCommand := Char(isc_info_reads);

  ErrorCode := GetPlainDriver.isc_database_info(@FStatusVector, @FHandle, 1, @DatabaseInfoCommand,
                           IBLocalBufferLength, @Buffer[0]);

  case ErrorCode of
    isc_network_error..isc_net_write_err:
      Result := -1
    else
      Result := 0;
  end;
end;

{**
   Start Interbase transaction
}
procedure TZInterbase6Connection.StartTransaction;

const
  Tpb_Access: array[boolean] of String = ('isc_tpb_write','isc_tpb_read');
  tpb_AutoCommit: array[boolean] of String = ('','isc_tpb_autocommit');

{ List of parameters that are assigned according to values of properties but
  could be overwritten by user.
  These parameters are all simple flags having no value so no splitting is required. }
type
  TOverwritableParams = (parTIL, parRW, parRecVer, parWait, parAutoCommit);
  TOverwritableParamValues = array[TOverwritableParams] of string;

  { Add all items from Src to Dest except those which define overwritable params.
    Value of these params are returned in OverwritableParams array. }
  procedure AddStrings(Dest, Src: TStrings; var OverwritableParams: TOverwritableParamValues);
  var
    I: Integer;
    SrcPar: string;
  begin
    for I := 0 to Src.Count - 1 do
    begin
      SrcPar := LowerCase(Src[I]);
      if (SrcPar = 'isc_tpb_consistency') or
         (SrcPar = 'isc_tpb_concurrency') or
         (SrcPar = 'isc_tpb_read_committed') then
        OverwritableParams[parTIL] := SrcPar
      else
      if (SrcPar = 'isc_tpb_wait') or
         (SrcPar = 'isc_tpb_nowait') then
        OverwritableParams[parWait] := SrcPar
      else
      if (SrcPar = 'isc_tpb_read') or
         (SrcPar = 'isc_tpb_write') then
        OverwritableParams[parRW] := SrcPar
      else
      if (SrcPar = 'isc_tpb_rec_version') or
         (SrcPar = 'isc_tpb_no_rec_version') then
        OverwritableParams[parRecVer] := SrcPar
      else
        Dest.Add(Src[I]);
    end;
  end;
var
  Params: TStrings;
  OverwritableParams: TOverwritableParamValues;
begin
  if FHandle <> 0 then begin
    if FTrHandle <> 0 then begin {CLOSE Last Transaction first!}
      GetPlainDriver.isc_commit_transaction(@FStatusVector, @FTrHandle);
      CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcTransaction);
      FTrHandle := 0;
    end;
    if fTPBs[AutoCommit][TransactIsolationLevel] = '' then begin
      Params := TStringList.Create;
      OverwritableParams[parRW] := tpb_Access[ReadOnly];
      OverwritableParams[parAutoCommit] := tpb_AutoCommit[AutoCommit];

      { Set transaction parameters by TransactIsolationLevel }
      case TransactIsolationLevel of
        tiReadCommitted:
          begin
            if (self as IZInterbase6Connection).GetHostVersion >= 4000000 then
              OverwritableParams[parRecVer] := 'isc_tpb_read_consistency'
            else
              OverwritableParams[parRecVer] := 'isc_tpb_rec_version';
            OverwritableParams[parWait] := 'isc_tpb_nowait';
            AddStrings(Params, Info, OverwritableParams);
            OverwritableParams[parRW] := tpb_Access[ReadOnly];
            OverwritableParams[parTIL] := 'isc_tpb_read_committed';
          end;
        tiRepeatableRead:
          begin
            OverwritableParams[parWait] := 'isc_tpb_nowait';
            AddStrings(Params, Info, OverwritableParams);
            OverwritableParams[parRW] := tpb_Access[ReadOnly];
            OverwritableParams[parTIL] := 'isc_tpb_concurrency';
          end;
        tiSerializable:
          begin
            AddStrings(Params, Info, OverwritableParams);
            OverwritableParams[parRW] := tpb_Access[ReadOnly];
            OverwritableParams[parTIL] := 'isc_tpb_consistency';
          end;
        else
        begin
          OverwritableParams[parRW] := tpb_Access[ReadOnly];
          { FB default values for non-standard TIL }
          OverwritableParams[parTIL] := 'isc_tpb_concurrency';
          OverwritableParams[parWait] := 'isc_tpb_wait';
          AddStrings(Params, Info, OverwritableParams);
        end;
      end;

      { Add overwitable parameters to the beginning of list }
      if OverwritableParams[parRW] <> '' then
        Params.Insert(0, OverwritableParams[parRW]);
      if OverwritableParams[parWait] <> '' then
        Params.Insert(0, OverwritableParams[parWait]);
      if OverwritableParams[parRecVer] <> '' then
        Params.Insert(0, OverwritableParams[parRecVer]);
      if OverwritableParams[parTIL] <> '' then
        Params.Insert(0, OverwritableParams[parTIL]);
      if OverwritableParams[parAutoCommit] <> '' then
        Params.Insert(0, OverwritableParams[parAutoCommit]);
    end else
      Params := nil;

    try
      if fTPBs[AutoCommit][TransactIsolationLevel] = '' then begin
        fTPBs[AutoCommit][TransactIsolationLevel] := GenerateTPB(FPlainDriver, Params, ConSettings, ConSettings^.ClientCodePage^.CP);
        GenerateTEB(@FHandle, fTPBs[AutoCommit][TransactIsolationLevel], fTEBs[AutoCommit][TransactIsolationLevel]);
      end;

      GetPlainDriver.isc_start_multiple(@FStatusVector, @FTrHandle, 1, @fTEBs[AutoCommit][TransactIsolationLevel]);
      CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcTransaction);
      DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol,
        'TRANSACTION STARTED.');
    finally
      if Params <> nil then
        FreeAndNil(Params);
    end
  end;
end;

{**
  Attempts to change the transaction isolation level to the one given.
  The constants defined in the interface <code>Connection</code>
  are the possible transaction isolation levels.

  <P><B>Note:</B> This method cannot be called while
  in the middle of a transaction.

  @param level one of the TRANSACTION_* isolation values with the
    exception of TRANSACTION_NONE; some databases may not support other values
  @see DatabaseMetaData#supportsTransactionIsolationLevel
}
procedure TZInterbase6Connection.SetTransactionIsolation(Level: TZTransactIsolationLevel);
begin
  if (Level <> TransactIsolationLevel) then begin
    CloseTransaction;
    Inherited SetTransactionIsolation(Level);
    //restart automatically happens on GetTrHandle
  end;
end;

{**
  Creates new database
  @param SQL a sql strinf for creation database
}
procedure TZInterbase6Connection.CreateNewDatabase(const SQL: RawByteString);
var
  TrHandle: TISC_TR_HANDLE;
begin
  GetPlainDriver.isc_dsql_execute_immediate(@FStatusVector, @FHandle, @TrHandle,
    Length(SQL), Pointer(sql), FDialect, nil);
  CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcExecute, SQL);
  //disconnect from the newly created database because the connection character set is NONE,
  //which usually nobody wants
  GetPlainDriver.isc_detach_database(@FStatusVector, @FHandle);
  CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcExecute, SQL);
  TrHandle := 0;
end;

function TZInterbase6Connection.GetBinaryEscapeString(const Value: RawByteString): String;
begin
  //http://tracker.firebirdsql.org/browse/CORE-2789
  if (GetMetadata.GetDatabaseInfo as IZInterbaseDatabaseInfo).SupportsBinaryInSQL then
    if (Length(Value)*2+3) < 32*1024
    then Result := GetSQLHexString(PAnsiChar(Value), Length(Value))
    else raise Exception.Create('Binary data out of range! Use parameters!')
  else raise Exception.Create('Your Firebird-Version does''t support Binary-Data in SQL-Statements! Use parameters!');
end;

function TZInterbase6Connection.GetBinaryEscapeString(const Value: TBytes): String;
begin
  //http://tracker.firebirdsql.org/browse/CORE-2789
  if (GetMetadata.GetDatabaseInfo as IZInterbaseDatabaseInfo).SupportsBinaryInSQL then
    if (Length(Value)*2+3) < 32*1024
    then Result := GetSQLHexString(PAnsiChar(Value), Length(Value))
    else raise Exception.Create('Binary data out of range! Use parameters!')
  else raise Exception.Create('Your Firebird-Version does''t support Binary-Data in SQL-Statements! Use parameters!');
end;

{**
  Creates a sequence generator object.
  @param Sequence a name of the sequence generator.
  @param BlockSize a number of unique keys requested in one trip to SQL server.
  @returns a created sequence object.
}
function TZInterbase6Connection.CreateSequence(const Sequence: string;
  BlockSize: Integer): IZSequence;
begin
  Result := TZInterbase6Sequence.Create(Self, Sequence, BlockSize);
end;

{**
  Sets this connection's auto-commit mode.
  If a connection is in auto-commit mode, then all its SQL
  statements will be executed and committed as individual
  transactions.  Otherwise, its SQL statements are grouped into
  transactions that are terminated by a call to either
  the method <code>commit</code> or the method <code>rollback</code>.
  By default, new connections are in auto-commit mode.

  The commit occurs when the statement completes or the next
  execute occurs, whichever comes first. In the case of
  statements returning a ResultSet, the statement completes when
  the last row of the ResultSet has been retrieved or the
  ResultSet has been closed. In advanced cases, a single
  statement may return multiple results as well as output
  parameter values. In these cases the commit occurs when all results and
  output parameter values have been retrieved.

  @param autoCommit true enables auto-commit; false disables auto-commit.
}
procedure TZInterbase6Connection.SetAutoCommit(Value: Boolean);
begin
  if (Value <> GetAutoCommit) then begin
    CloseTransaction;
    inherited SetAutoCommit(Value);
    //restart automatically happens on GetTrHandle
  end;
end;

{**
  Puts this connection in read-only mode as a hint to enable
  database optimizations.

  <P><B>Note:</B> This method cannot be called while in the
  middle of a transaction.

  @param readOnly true enables read-only mode; false disables
    read-only mode.
}
procedure TZInterbase6Connection.SetReadOnly(Value: Boolean);
begin
  if (ReadOnly <> Value) then begin
    CloseTransaction;
    inherited SetReadOnly(Value);
    //restart automatically happens on GetTrHandle
  end;
end;

{ TZInterbase6CachedResolver }

{**
  Forms a where clause for SELECT statements to calculate default values.
  @param Columns a collection of key columns.
  @param OldRowAccessor an accessor object to old column values.
}
function TZInterbase6CachedResolver.FormCalculateStatement(
  Columns: TObjectList): string;
// --> ms, 30/10/2005
var
   iPos: Integer;
begin
  Result := inherited FormCalculateStatement(Columns);
  if Result <> '' then
  begin
    iPos := ZFastCode.pos('FROM', uppercase(Result));
    if iPos > 0 then
      Result := copy(Result, 1, iPos+3) + ' RDB$DATABASE'
    else
      Result := Result + ' FROM RDB$DATABASE';
  end;
// <-- ms
end;

{ TZInterbase6Sequence }

{**
  Gets the current unique key generated by this sequence.
  @param the next generated unique key.
}
function TZInterbase6Sequence.GetCurrentValue: Int64;
var
  Statement: IZStatement;
  ResultSet: IZResultSet;
begin
  Statement := Connection.CreateStatement;
  ResultSet := Statement.ExecuteQuery(Format(
    'SELECT %s FROM RDB$DATABASE', [GetCurrentValueSQL]));
  if ResultSet.Next then
    Result := ResultSet.GetLong(FirstDbcIndex)
  else
    Result := inherited GetCurrentValue;
  ResultSet.Close;
  Statement.Close;
end;

{**
  Gets the next unique key generated by this sequence.
  @param the next generated unique key.
}
function TZInterbase6Sequence.GetCurrentValueSQL: string;
var
  QuotedName: string;
begin
  QuotedName := GetConnection.GetMetadata.GetIdentifierConvertor.Quote(Name);
  Result := Format(' GEN_ID(%s, 0) ', [QuotedName]);
end;

function TZInterbase6Sequence.GetNextValue: Int64;
var
  Statement: IZStatement;
  ResultSet: IZResultSet;
begin
  Statement := Connection.CreateStatement;
  ResultSet := Statement.ExecuteQuery(
    Format('SELECT %s FROM RDB$DATABASE', [GetNextValueSQL]));
  if ResultSet.Next then
    Result := ResultSet.GetLong(FirstDbcIndex)
  else
    Result := inherited GetNextValue;
  ResultSet.Close;
  Statement.Close;
end;

function TZInterbase6Sequence.GetNextValueSQL: string;
var
  QuotedName: string;
begin
  QuotedName := GetConnection.GetMetadata.GetIdentifierConvertor.Quote(Name);
  if (Connection.GetMetadata.GetDatabaseInfo as IZInterbaseDatabaseInfo).SupportsNextValueFor and (BlockSize = 1) then
    Result := Format(' NEXT VALUE FOR %s ', [QuotedName])
  else
    Result := Format(' GEN_ID(%s, %d) ', [QuotedName, BlockSize]);
end;

{ TZIBTransactionManager }

procedure TZIBTransactionManager.AddToOrphanList(const Obj: TZIBTransaction);
var I: Integer;
begin
  I := FTransactions.IndexOf(Obj);
  {$IFDEF DEBUG}Assert(I > -1, 'Wrong orphan behavior');{$ENDIF}
  FOrphanTransactions.Add(Obj);
  FTransactions[i] := nil;
  FTransactions.Delete(I);
end;

function TZIBTransactionManager.Commit: Integer;
begin
  GetActiveTransaction.Rollback;
  Result := FTransactions.Count;
end;

constructor TZIBTransactionManager.Create(Owner: TZInterbase6Connection);
begin
  FTransactions := TObjectList.Create(True);
  FOrphanTransactions := TObjectList.Create(True);
  FOwner := Owner;
end;

function TZIBTransactionManager.GetActiveTransaction: TZIBTransaction;
begin
  Result := nil;
end;

function TZIBTransactionManager.GetTrHandle: PISC_TR_HANDLE;
begin
  Result := GetActiveTransaction.GetTrHandle;
end;

procedure TZIBTransactionManager.ReleaseImmediat(
  const Sender: IImmediatelyReleasable; var AError: EZSQLConnectionLost);
var I: Integer;
begin
  for i := 0 to FOrphanTransactions.Count -1 do
    TZIBTransaction(FOrphanTransactions[i]).ReleaseImmediat(Sender, AError);
  FOrphanTransactions.Clear;
  for i := 0 to FTransactions.Count -1 do
    TZIBTransaction(FTransactions[i]).ReleaseImmediat(Sender, AError);
  FTransactions.Clear;
end;

procedure TZIBTransactionManager.RemoveOrphan(const Obj: TZIBTransaction);
begin
end;

function TZIBTransactionManager.Rollback: Integer;
begin
  GetActiveTransaction.Rollback;
  Result := FTransactions.Count;
end;

function TZIBTransactionManager.StartTransaction: Integer;
begin
  with fOwner do
    Result := Self.StartTransaction(TransactIsolationLevel, AutoCommit, ReadOnly)
end;

function TZIBTransactionManager.StartTransaction(
  TransactIsolationLevel: TZTransactIsolationLevel; AutoCommit,
  ReadOnly: Boolean): Integer;
begin
  Result := -1;
end;

{ TZIBTransaction }

procedure TZIBTransaction.BeforeDestruction;
begin
  try
    FOpenCursors.Clear;
    if fDoCommit
    then Commit
    else RollBack;
  finally
    FreeAndNil(FOpenCursors);
    inherited BeforeDestruction;
  end;
end;

procedure TZIBTransaction.Commit;
var Status: ISC_STATUS;
begin
  if FTrHandle <> 0 then with FOwner.FOwner do try
    if (FOpenCursors.Count = 0)
    then Status := FPlainDriver.isc_commit_transaction(@FStatusVector, @FTrHandle)
    else begin
      fDoCommit := True;
      fDoLog := False;
      Status := FPlainDriver.isc_commit_retaining(@FStatusVector, @FTrHandle);
      FOwner.AddToOrphanList(Self);
    end;
    if Status <> 0 then
      CheckInterbase6Error(FPlainDriver, FStatusVector, Self);
  finally
    if fDoLog and DriverManager.HasLoggingListener then
      DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol, 'TRANSACTION COMMIT');
  end;
end;

constructor TZIBTransaction.Create(const Owner: TZIBTransactionManager);
begin
  FOwner := Owner;
  ConSettings := Owner.FOwner.ConSettings;
  FOpenCursors := TList.Create;
  fDoLog := True;
end;

procedure TZIBTransaction.DeRegisterOpenCursor(const RS: IZResultSet);
var I: Integer;
begin
  {$IFDEF DEBUG}Assert(FOpenCursors <> nil, 'Wrong DeRegisterOpenCursor beahvior'); {$ENDIF DEBUG}
  I := FOpenCursors.IndexOf(Pointer(RS));
  {$IFDEF DEBUG}Assert(I > -1, 'Wrong DeRegisterOpenCursor beahvior'); {$ENDIF DEBUG}
  FOpenCursors.Delete(I);
end;

function TZIBTransaction.GetTrHandle: PISC_TR_HANDLE;
begin
  if FTrHandle = 0 then
    StartTransaction;
  Result := @FTrHandle
end;

procedure TZIBTransaction.RegisterOpenCursor(const RS: IZResultSet;
  Out OnCursorClose: TOnCursorClose);
begin
  OnCursorClose := DeRegisterOpenCursor;
  FOpenCursors.Add(Pointer(RS));
end;

procedure TZIBTransaction.ReleaseImmediat(const Sender: IImmediatelyReleasable;
  var AError: EZSQLConnectionLost);
begin
  FTrHandle := 0;
  FOpenCursors.Clear;
end;

procedure TZIBTransaction.Rollback;
var Status: ISC_STATUS;
begin
  if FTrHandle <> 0 then with FOwner.FOwner do try
    if (FOpenCursors.Count = 0)
    then Status := FPlainDriver.isc_rollback_transaction(@FStatusVector, @FTrHandle)
    else begin
      fDoCommit := False;
      fDoLog := False;
      Status := FPlainDriver.isc_rollback_retaining(@FStatusVector, @FTrHandle);
      FOwner.AddToOrphanList(Self);
    end;
    if Status <> 0 then
      CheckInterbase6Error(FPlainDriver, FStatusVector, Self);
  finally
    if fDoLog and DriverManager.HasLoggingListener then
      DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol, 'TRANSACTION ROLLBACK');
  end;
end;

procedure TZIBTransaction.StartTransaction;
begin
  {$IFDEF DEBUG}Assert(FTrHandle = 0, 'Wrong transaction behavior');{$ENDIF}
  with fOwner.FOwner do begin
    if FPlainDriver.isc_start_multiple(@FStatusVector, @FTrHandle, 1, @fTEBs[AutoCommit][TransactIsolationLevel]) <> 0 then
      CheckInterbase6Error(FPlainDriver, FStatusVector, Self, lcTransaction);
    DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol, 'TRANSACTION STARTED.');
  end;
end;

initialization
  Interbase6Driver := TZInterbase6Driver.Create;
  DriverManager.RegisterDriver(Interbase6Driver);

finalization
  if Assigned(DriverManager) then
    DriverManager.DeregisterDriver(Interbase6Driver);
  Interbase6Driver := nil;
{$ENDIF ZEOS_DISABLE_INTERBASE} //if set we have an empty unit
end.
