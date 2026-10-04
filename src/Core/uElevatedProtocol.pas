unit uElevatedProtocol;

{ Messages between the program and its administrator helper process
  (uElevatedHelper, uElevatedVfs). A message is a 4-byte little-endian length
  followed by a UTF-8 JSON object. The program sends requests (copy, move,
  delete, create folder, write text, cancel); the helper answers each request
  with progress messages and one final "done" message that carries the error,
  if any. The helper runs only these operations on plain local paths; there is
  no way to start a program through it. }

interface

uses
  System.SysUtils, uVfsTypes;

const
  cElevatedMaxFrame = 16 * 1024 * 1024;
  /// <summary>Largest text a write-text request may carry.</summary>
  cElevatedMaxText = 8 * 1024 * 1024;

type
  TElevatedOp = (eoHello, eoCopy, eoMove, eoDelete, eoMkDir, eoWriteText,
    eoCancel, eoQuit);

  TElevatedRequest = record
    Id: Integer;
    Op: TElevatedOp;
    FromURI: string;
    ToURI: string;
    /// <summary>Delete: Recycle Bin or permanent.</summary>
    Mode: TVfsDeleteMode;
    Overwrite: Boolean;
    Preserve: Boolean;
    Text: string;
    /// <summary>Ordinal of TTextFileEncoding.</summary>
    Encoding: Integer;
    /// <summary>Hello: the secret the program passed to the helper on its
    /// command line.</summary>
    Nonce: string;
  end;

  TElevatedReplyKind = (erkHello, erkProgress, erkDone);

  TElevatedReply = record
    Id: Integer;
    Kind: TElevatedReplyKind;
    Done, Total, ItemDone, ItemTotal: Int64;
    Name, Src, Dst: string;
    Ok: Boolean;
    Code: TVfsErrorCode;
    Msg: string;
    URI: string;
  end;

function EncodeRequest(const ARequest: TElevatedRequest): TBytes;
function DecodeRequest(const APayload: TBytes; out ARequest: TElevatedRequest): Boolean;
function EncodeReply(const AReply: TElevatedReply): TBytes;
function DecodeReply(const APayload: TBytes; out AReply: TElevatedReply): Boolean;

/// <summary>APayload with its length in front, ready to write.</summary>
function FrameBytes(const APayload: TBytes): TBytes;
/// <summary>Takes one whole message off the front of ABuffer. False when the
/// buffer holds only part of one; AInvalid is set when the announced length is
/// beyond cElevatedMaxFrame (the connection must be dropped).</summary>
function TryTakeFrame(var ABuffer: TBytes; out APayload: TBytes;
  out AInvalid: Boolean): Boolean;

/// <summary>True for a file URI of a plain local path (file:///C:/dir or a UNC
/// share): not an archive, not a virtual folder, not a relative or empty path.</summary>
function IsElevatableUri(const AURI: string): Boolean;
/// <summary>Whether the helper may run ARequest; AReason says why not.</summary>
function ValidateRequest(const ARequest: TElevatedRequest; out AReason: string): Boolean;

implementation

uses
  System.Classes, System.JSON;

function EncodeRequest(const ARequest: TElevatedRequest): TBytes;
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  try
    O.AddPair('id', TJSONNumber.Create(ARequest.Id));
    O.AddPair('op', TJSONNumber.Create(Ord(ARequest.Op)));
    O.AddPair('from', ARequest.FromURI);
    O.AddPair('to', ARequest.ToURI);
    O.AddPair('mode', TJSONNumber.Create(Ord(ARequest.Mode)));
    O.AddPair('overwrite', TJSONBool.Create(ARequest.Overwrite));
    O.AddPair('preserve', TJSONBool.Create(ARequest.Preserve));
    O.AddPair('text', ARequest.Text);
    O.AddPair('enc', TJSONNumber.Create(ARequest.Encoding));
    O.AddPair('nonce', ARequest.Nonce);
    Result := TEncoding.UTF8.GetBytes(O.ToJSON);
  finally
    O.Free;
  end;
end;

function JsonInt(AObj: TJSONObject; const AName: string; ADefault: Int64): Int64;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsInt64
  else
    Result := ADefault;
end;

function JsonStr(AObj: TJSONObject; const AName: string): string;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  if V is TJSONString then
    Result := TJSONString(V).Value
  else
    Result := '';
end;

function JsonBool(AObj: TJSONObject; const AName: string): Boolean;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  Result := (V is TJSONBool) and TJSONBool(V).AsBoolean;
end;

function ParseObject(const APayload: TBytes): TJSONObject;
var
  V: TJSONValue;
begin
  Result := nil;
  try
    V := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(APayload));
  except
    Exit;
  end;
  if V is TJSONObject then
    Result := TJSONObject(V)
  else
    V.Free;
end;

function DecodeRequest(const APayload: TBytes; out ARequest: TElevatedRequest): Boolean;
var
  O: TJSONObject;
  OpNo, ModeNo: Int64;
begin
  ARequest := Default(TElevatedRequest);
  O := ParseObject(APayload);
  if O = nil then
    Exit(False);
  try
    OpNo := JsonInt(O, 'op', -1);
    ModeNo := JsonInt(O, 'mode', 0);
    Result := (OpNo >= Ord(Low(TElevatedOp))) and (OpNo <= Ord(High(TElevatedOp))) and
      (ModeNo >= Ord(Low(TVfsDeleteMode))) and (ModeNo <= Ord(High(TVfsDeleteMode)));
    if not Result then
      Exit;
    ARequest.Id := JsonInt(O, 'id', 0);
    ARequest.Op := TElevatedOp(OpNo);
    ARequest.FromURI := JsonStr(O, 'from');
    ARequest.ToURI := JsonStr(O, 'to');
    ARequest.Mode := TVfsDeleteMode(ModeNo);
    ARequest.Overwrite := JsonBool(O, 'overwrite');
    ARequest.Preserve := JsonBool(O, 'preserve');
    ARequest.Text := JsonStr(O, 'text');
    ARequest.Encoding := JsonInt(O, 'enc', 0);
    ARequest.Nonce := JsonStr(O, 'nonce');
  finally
    O.Free;
  end;
end;

function EncodeReply(const AReply: TElevatedReply): TBytes;
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  try
    O.AddPair('id', TJSONNumber.Create(AReply.Id));
    O.AddPair('kind', TJSONNumber.Create(Ord(AReply.Kind)));
    O.AddPair('done', TJSONNumber.Create(AReply.Done));
    O.AddPair('total', TJSONNumber.Create(AReply.Total));
    O.AddPair('idone', TJSONNumber.Create(AReply.ItemDone));
    O.AddPair('itotal', TJSONNumber.Create(AReply.ItemTotal));
    O.AddPair('name', AReply.Name);
    O.AddPair('src', AReply.Src);
    O.AddPair('dst', AReply.Dst);
    O.AddPair('ok', TJSONBool.Create(AReply.Ok));
    O.AddPair('code', TJSONNumber.Create(Ord(AReply.Code)));
    O.AddPair('msg', AReply.Msg);
    O.AddPair('uri', AReply.URI);
    Result := TEncoding.UTF8.GetBytes(O.ToJSON);
  finally
    O.Free;
  end;
end;

function DecodeReply(const APayload: TBytes; out AReply: TElevatedReply): Boolean;
var
  O: TJSONObject;
  KindNo, CodeNo: Int64;
begin
  AReply := Default(TElevatedReply);
  O := ParseObject(APayload);
  if O = nil then
    Exit(False);
  try
    KindNo := JsonInt(O, 'kind', -1);
    CodeNo := JsonInt(O, 'code', 0);
    Result := (KindNo >= Ord(Low(TElevatedReplyKind))) and
      (KindNo <= Ord(High(TElevatedReplyKind))) and
      (CodeNo >= Ord(Low(TVfsErrorCode))) and (CodeNo <= Ord(High(TVfsErrorCode)));
    if not Result then
      Exit;
    AReply.Id := JsonInt(O, 'id', 0);
    AReply.Kind := TElevatedReplyKind(KindNo);
    AReply.Done := JsonInt(O, 'done', 0);
    AReply.Total := JsonInt(O, 'total', 0);
    AReply.ItemDone := JsonInt(O, 'idone', 0);
    AReply.ItemTotal := JsonInt(O, 'itotal', 0);
    AReply.Name := JsonStr(O, 'name');
    AReply.Src := JsonStr(O, 'src');
    AReply.Dst := JsonStr(O, 'dst');
    AReply.Ok := JsonBool(O, 'ok');
    AReply.Code := TVfsErrorCode(CodeNo);
    AReply.Msg := JsonStr(O, 'msg');
    AReply.URI := JsonStr(O, 'uri');
  finally
    O.Free;
  end;
end;

function FrameBytes(const APayload: TBytes): TBytes;
var
  Len: Cardinal;
begin
  Len := Length(APayload);
  SetLength(Result, 4 + Length(APayload));
  Result[0] := Len and $FF;
  Result[1] := (Len shr 8) and $FF;
  Result[2] := (Len shr 16) and $FF;
  Result[3] := (Len shr 24) and $FF;
  if Len > 0 then
    Move(APayload[0], Result[4], Len);
end;

function TryTakeFrame(var ABuffer: TBytes; out APayload: TBytes;
  out AInvalid: Boolean): Boolean;
var
  Len: Cardinal;
begin
  Result := False;
  AInvalid := False;
  APayload := nil;
  if Length(ABuffer) < 4 then
    Exit;
  Len := Cardinal(ABuffer[0]) or (Cardinal(ABuffer[1]) shl 8) or
    (Cardinal(ABuffer[2]) shl 16) or (Cardinal(ABuffer[3]) shl 24);
  if Len > cElevatedMaxFrame then
  begin
    AInvalid := True;
    Exit;
  end;
  if Cardinal(Length(ABuffer)) < 4 + Len then
    Exit;
  SetLength(APayload, Len);
  if Len > 0 then
    Move(ABuffer[4], APayload[0], Len);
  Delete(ABuffer, 0, 4 + Len);
  Result := True;
end;

function IsElevatableUri(const AURI: string): Boolean;
var
  Path: string;
begin
  Result := False;
  // Only a file URI: a bare name would be resolved against the helper's own
  // current folder, which is not where the program's user means.
  if not Trim(AURI).StartsWith('file:', True) or HasArchiveChain(AURI) then
    Exit;
  Path := FileUriToPath(AURI);
  if Path = '' then
    Exit;
  // A drive path (C:\...) or a UNC share (\\host\share\...); the path is
  // already normalized, so ".." cannot be left in it.
  Result := ((Length(Path) >= 3) and (Path[2] = ':') and (Path[3] = '\')) or
    (Copy(Path, 1, 2) = '\\');
end;

function ValidateRequest(const ARequest: TElevatedRequest; out AReason: string): Boolean;
begin
  AReason := '';
  case ARequest.Op of
    eoCopy, eoMove:
      Result := IsElevatableUri(ARequest.FromURI) and IsElevatableUri(ARequest.ToURI);
    eoDelete, eoMkDir, eoWriteText:
      Result := IsElevatableUri(ARequest.FromURI);
    eoHello, eoCancel, eoQuit:
      Result := True;
  else
    Result := False;
  end;
  if (ARequest.Op = eoWriteText) and (Length(ARequest.Text) > cElevatedMaxText) then
    Result := False;
  if not Result then
    AReason := 'Request refused';
end;

end.
