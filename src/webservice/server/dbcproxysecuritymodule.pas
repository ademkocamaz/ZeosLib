{*********************************************************}
{                                                         }
{                 Zeos Database Objects                   }
{                WebService Proxy Server                  }
{                                                         }
{         Originally written by Jan Baumgarten            }
{                                                         }
{*********************************************************}

{@********************************************************}
{    Copyright (c) 1999-2020 Zeos Development Group       }
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
{   https://zeoslib.sourceforge.io/ (FORUM)               }
{   http://sourceforge.net/p/zeoslib/tickets/ (BUGTRACKER)}
{   svn://svn.code.sf.net/p/zeoslib/code-0/trunk (SVN)    }
{                                                         }
{   http://www.sourceforge.net/projects/zeoslib.          }
{                                                         }
{                                                         }
{                                 Zeos Development Group. }
{********************************************************@}

unit DbcProxySecurityModule;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, IniFiles,
  ZDbcIntfs,
  yubiotp,
  GoogleOTP,
  md5crypt;

type
  TZAbstractSecurityModule = class
    function CheckPassword(var UserName, Password: String; const ConnectionName: String): Boolean; virtual; abstract;
    procedure LoadConfig(IniFile: TIniFile; const Section: String); virtual; abstract;
  end;

  TZYubiOtpSecurityModule = class(TZAbstractSecurityModule)
  protected
    FYubikeysName: String;
    FAddDatabase: Boolean;
    FDatabaseSeparator: String;
    FBaseURL: String;
    FClientID: Integer;
    FSecretKey: String;
  public
    function CheckPassword(var UserName, Password: String; const ConnectionName: String): Boolean; override;
    procedure LoadConfig(IniFile: TIniFile; const Section: String); override;
  end;

  TZTotpSecurityModule = class(TZAbstractSecurityModule)
  protected
    FSecretsName: String;
    FAddDatabase: Boolean;
    FDatabaseSeparator: String;
  public
    function CheckPassword(var UserName, Password: String; const ConnectionName: String): Boolean; override;
    procedure LoadConfig(IniFile: TIniFile; const Section: String); override;
  end;

  TZIntegratedSecurityModule = class(TZAbstractSecurityModule)
  protected
    FDBUser: String;
    FDBPassword: String;
    FPasswordSQL: String;
    FReplacementUser: String;
    FReplacementPassword: String;
  public
    function CheckPassword(var UserName, Password: String; const ConnectionName: String): Boolean; override;
    procedure LoadConfig(IniFile: TIniFile; const Section: String); override;
  end;

  TZChainedSecurityModule = class(TZAbstractSecurityModule)
  protected
    FModuleChain: Array of TZAbstractSecurityModule;
  public
    function CheckPassword(var UserName, Password: String; const ConnectionName: String): Boolean; override;
    procedure LoadConfig(IniFile: TIniFile; const Section: String); override;
    destructor Destroy; override;
  end;

  TZAlternateSecurityModule = class(TZAbstractSecurityModule)
  protected
    FModuleChain: Array of TZAbstractSecurityModule;
  public
    function CheckPassword(var UserName, Password: String; const ConnectionName: String): Boolean; override;
    procedure LoadConfig(IniFile: TIniFile; const Section: String); override;
    destructor Destroy; override;
  end;

function GetSecurityModule(TypeName: String): TZAbstractSecurityModule;

implementation

uses DbcProxyConfigManager, zeosproxy_imp, StrUtils, Types, ZExceptions;

function GetSecurityModule(TypeName: String): TZAbstractSecurityModule;
begin
  TypeName := LowerCase(TypeName);
  if TypeName = 'yubiotp' then
    Result := TZYubiOtpSecurityModule.Create
  else if TypeName = 'totp' then
    Result := TZTotpSecurityModule.Create
  else if TypeName = 'integrated' then
    Result := TZIntegratedSecurityModule.Create
  else if TypeName = 'chained' then
    Result := TZChainedSecurityModule.Create
  else if TypeName = 'alternate' then
    Result := TZChainedSecurityModule.Create
  else
    raise EZSQLException.Create('Security module of type ' + TypeName + ' is unknown.');
end;

function TZYubiOtpSecurityModule.CheckPassword(var UserName, Password: String; const ConnectionName: String): Boolean;
var
  Yubikeys: TStringList;
  AllowedKeys: String;
  PublicIdentity: String;
  YubikeysUser: String;
  YubiStatus: TYubiOtpStatus;
  RemainingPassword: String;
begin
  Yubikeys := TStringList.Create;
  try
    Yubikeys.NameValueSeparator:=':';
    Yubikeys.LoadFromFile(FYubikeysName, TEncoding.UTF8);
    YubikeysUser := UserName;
    if FAddDatabase then
      YubikeysUser := YubikeysUser + FDatabaseSeparator + ConnectionName;
    AllowedKeys := ':' + Yubikeys.Values[UserName] + ':';
    PublicIdentity := GetYubikeyIdentity(Password);
    Result := Pos(':' + PublicIdentity + ':', AllowedKeys) > 0;
    if not Result then
      raise EZSQLException.Create('This yubikey cannot be used for this user.');
  finally
    FreeAndNil(Yubikeys);
  end;

  if Result then begin
    YubiStatus := VerifyYubiOtp(FBaseURL, Password, RemainingPassword, FClientID, FSecretKey);
    Result := YubiStatus = yosOk;
    RaiseYubiOtpError(YubiStatus);
    Password := RemainingPassword;
  end;
end;

procedure TZYubiOtpSecurityModule.LoadConfig(IniFile: TIniFile; const Section: String);
begin
  FYubikeysName := IniFile.ReadString(Section, 'Yubikeys File', '');
  FAddDatabase := IniFile.ReadBool(Section, 'Add Database To Username', false);
  FDatabaseSeparator := IniFile.ReadString(Section, 'Database Separator', '@');
  FBaseURL := IniFile.ReadString(Section, 'Base URL', 'https://api.yubico.com/wsapi/2.0/verify');
  FClientID := IniFile.ReadInteger(Section, 'Client ID', 0);
  FSecretKey := IniFile.ReadString(Section, 'Secret Key', '');
end;

{------------------------------------------------------------------------------}

function TZTotpSecurityModule.CheckPassword(var UserName, Password: String; const ConnectionName: String): Boolean;
var
  Secrets: TStringList;
  Secret: String;
  SecretsUser: String;
  RemainingPassword: String;
  OTP: String;
begin
  Secrets := TStringList.Create;
  try
    Secrets.NameValueSeparator:=':';
    Secrets.LoadFromFile(FSecretsName, TEncoding.UTF8);
    SecretsUser := UserName;
    if FAddDatabase then
      SecretsUser := SecretsUser + FDatabaseSeparator + ConnectionName;
    Secret := Secrets.Values[UserName];
    Result := Secret <> '';
  finally
    FreeAndNil(Secrets);
  end;

  if Result then begin
    OTP := Copy(Password, Length(Password) - 6 + 1, 6);
    RemainingPassword := Copy(Password, 1, Length(Password) - 6);
    Password := RemainingPassword;
    Result := GoogleOTP.ValidateTOPT(Secret, StrToIntDef(OTP, 0));
  end;

  if not Result then
    raise EZSQLException.Create('Could not validate username / password.');
end;

procedure TZTotpSecurityModule.LoadConfig(IniFile: TIniFile; const Section: String);
begin
  FSecretsName := IniFile.ReadString(Section, 'Secrets File', '');
  FAddDatabase := IniFile.ReadBool(Section, 'Add Database To Username', false);
  FDatabaseSeparator := IniFile.ReadString(Section, 'Database Separator', '@');
end;

{------------------------------------------------------------------------------}

function TZIntegratedSecurityModule.CheckPassword(var UserName, Password: String; const ConnectionName: String): Boolean;
var
  URL: String;
  Conn: IZConnection;
  Stmt: IZPreparedStatement;
  RS: IZResultSet;
  PropertiesList: TStringList;
  CryptPwdDB: UTF8String;
  CryptPwdUser: UTF8String;
  pwdStart: String;
begin
  Result := False;

  URL := ConfigManager.ConstructUrl(ConnectionName, FDBUser, FDBPassword, False);
  PropertiesList := TStringList.Create;
  try
    Conn := DriverManager.GetConnectionWithParams(Url, PropertiesList);
  finally
    FreeAndNil(PropertiesList);
  end;

  Stmt := Conn.PrepareStatement(FPasswordSQL);
  Stmt.SetResultSetConcurrency(rcReadOnly);
  Stmt.SetResultSetType(rtForwardOnly);
  Stmt.SetString(FirstDbcIndex, UserName);
  if Stmt.ExecutePrepared then begin
    RS := Stmt.GetResultSet;
    if Assigned(RS) and RS.IsBeforeFirst then begin
      RS.Next;
      try
        CryptPwdDB := RS.GetUTF8String(FirstDbcIndex);
      finally
        RS.Close;
      end;
    end;
  end;
  RS := nil;
  Stmt := nil;
  Conn.Close;
  Conn := nil;


  pwdStart := Copy(CryptPwdDB, 1, 3);
  if pwdStart = '$1$' then //cryptmd5
    CryptPwdUser := crypt_md5(Password, CryptPwdDB)
  else if pwdStart = 'md5' then //md5 by PpostgreSQL
    CryptPwdUser := crypt_md5pg(Password, UserName)
  else
    CryptPwdUser := '$$$$$$$$$$'; // $-Signs shouldn't make up a valid crypted password.
  Result := CryptPwdDB = CryptPwdUser;

  if FReplacementUser <> '' then begin
    UserName := FReplacementUser;
    Password := FReplacementPassword;
  end;
end;

procedure TZIntegratedSecurityModule.LoadConfig(IniFile: TIniFile; const Section: String);
begin
  FDBUser := IniFile.ReadString(Section, 'DB User', '');
  FDBPassword := IniFile.ReadString(Section, 'DB Password', '');
  FReplacementUser := IniFile.ReadString(Section, 'Replacement User', '');
  FReplacementPassword := IniFile.ReadString(Section, 'Replacement Password', '');
  FPasswordSQL := IniFile.ReadString(Section, 'Password SQL', '');;
end;

{------------------------------------------------------------------------------}

function TZChainedSecurityModule.CheckPassword(var UserName, Password: String; const ConnectionName: String): Boolean;
var
  x: Integer;
begin
  Result := True;
  for x := 0 to Length(FModuleChain) - 1  do begin
    try
      Result := Result and FModuleChain[x].CheckPassword(UserName, Password, ConnectionName);
    except
      on E: Exception do begin
        Logger.Warning('Unexpected exception while calling an authentication module:  ' + E.Message);
        Result := false;
      end;
    end;
    if not Result then break;
  end;
end;

procedure TZChainedSecurityModule.LoadConfig(IniFile: TIniFile; const Section: String);
var
  Modules: String;
  TypeList: TStringDynArray;
  x: Integer;
  SectionName: String;
begin
  Modules := IniFile.ReadString(Section, 'Module List', '');
  TypeList := SplitString(Modules, ',');
  for x := Length(TypeList) - 1 downto 0 do
    TypeList[x] := Trim(TypeList[x]);
  for x := Length(TypeList) - 1 downto 0 do
    if TypeList[x] = '' then
      Delete(TypeList, x, 1);
  if Length(TypeList) = 0 then
    raise EZSQLException.Create('A chained security module may not have an empty Module List');

  SetLength(FModuleChain, Length(TypeList));
  for x := 0 to Length(TypeList) - 1 do begin
    SectionName := ConfigManager.SecurityPrefix + TypeList[x];
    FModuleChain[x] := GetSecurityModule(TypeList[x]);
    FModuleChain[x].LoadConfig(IniFile, SectionName);
  end;
end;

destructor TZChainedSecurityModule.Destroy;
var
  x: Integer;
begin
  for x := 0 to Length(FModuleChain) - 1 do
    if Assigned(FModuleChain[x]) then;
      FreeAndNil(FModuleChain[x]);
  inherited;
end;

{------------------------------------------------------------------------------}

function TZAlternateSecurityModule.CheckPassword(var UserName, Password: String; const ConnectionName: String): Boolean;
var
  x: Integer;
begin
  Result := False;
  for x := 0 to Length(FModuleChain) - 1  do begin
    try
      Result := Result or FModuleChain[x].CheckPassword(UserName, Password, ConnectionName);
    except
      on E: Exception do begin
        Logger.Warning('Unexpected exception while calling an authentication module:  ' + E.Message);
      end;
    end;
    if Result then break;
  end;
end;

procedure TZAlternateSecurityModule.LoadConfig(IniFile: TIniFile; const Section: String);
var
  Modules: String;
  ModuleList: TStringDynArray;
  x: Integer;
  SectionName: String;
begin
  Modules := IniFile.ReadString(Section, 'Module List', '');
  ModuleList := SplitString(Modules, ',');
  for x := Length(ModuleList) - 1 downto 0 do
    ModuleList[x] := Trim(ModuleList[x]);
  for x := Length(ModuleList) - 1 downto 0 do
    if ModuleList[x] = '' then
      Delete(ModuleList, x, 1);
  if Length(ModuleList) = 0 then
    raise EZSQLException.Create('An alternate security module may not have an empty Module List');

  SetLength(FModuleChain, Length(ModuleList));
  for x := 0 to Length(ModuleList) - 1 do begin
    SectionName := ConfigManager.SecurityPrefix + ModuleList[x];
    FModuleChain[x] := GetSecurityModule(IniFile.ReadString(SectionName, 'type', ''));
    FModuleChain[x].LoadConfig(IniFile, SectionName);
  end;
end;

destructor TZAlternateSecurityModule.Destroy;
var
  x: Integer;
begin
  for x := 0 to Length(FModuleChain) - 1 do
    if Assigned(FModuleChain[x]) then;
      FreeAndNil(FModuleChain[x]);
  inherited;
end;

end.
