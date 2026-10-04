unit TestElevatedProtocol;

{ Messages of the administrator helper (uElevatedProtocol): encoding, framing
  and the check of which requests the helper may run. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestElevatedProtocol = class
  public
    [Test] procedure TestRequestRoundTrip;
    [Test] procedure TestReplyRoundTrip;
    [Test] procedure TestDecodeRejectsGarbage;
    [Test] procedure TestDecodeRejectsUnknownOp;
    [Test] procedure TestFramingAcrossPartialReads;
    [Test] procedure TestTwoFramesInOneRead;
    [Test] procedure TestOversizeFrameIsInvalid;
    [Test] procedure TestElevatableUris;
    [Test] procedure TestValidateRequest;
  end;

implementation

uses
  System.SysUtils, uVfsTypes, uElevatedProtocol;

procedure TTestElevatedProtocol.TestRequestRoundTrip;
var
  Req, Back: TElevatedRequest;
begin
  Req := Default(TElevatedRequest);
  Req.Id := 41;
  Req.Op := eoWriteText;
  Req.FromURI := PathToFileUri('C:\Program Files\App\conf.ini');
  Req.ToURI := PathToFileUri('C:\Temp\Папка\b.txt');
  Req.Mode := vdmPermanent;
  Req.Overwrite := True;
  Req.Preserve := True;
  Req.Text := 'строка "в кавычках"'#13#10'вторая';
  Req.Encoding := 2;
  Req.Nonce := 'n-1';
  Assert.IsTrue(DecodeRequest(EncodeRequest(Req), Back));
  Assert.AreEqual(Req.Id, Back.Id);
  Assert.IsTrue(Back.Op = eoWriteText);
  Assert.AreEqual(Req.FromURI, Back.FromURI);
  Assert.AreEqual(Req.ToURI, Back.ToURI);
  Assert.IsTrue(Back.Mode = vdmPermanent);
  Assert.IsTrue(Back.Overwrite);
  Assert.IsTrue(Back.Preserve);
  Assert.AreEqual(Req.Text, Back.Text);
  Assert.AreEqual(2, Back.Encoding);
  Assert.AreEqual('n-1', Back.Nonce);
end;

procedure TTestElevatedProtocol.TestReplyRoundTrip;
var
  Rep, Back: TElevatedReply;
begin
  Rep := Default(TElevatedReply);
  Rep.Id := 7;
  Rep.Kind := erkProgress;
  Rep.Done := 5000000000;
  Rep.Total := 9000000000;
  Rep.ItemDone := 10;
  Rep.ItemTotal := 20;
  Rep.Name := 'a.bin';
  Rep.Src := 'C:\s\a.bin';
  Rep.Dst := 'C:\d\a.bin';
  Assert.IsTrue(DecodeReply(EncodeReply(Rep), Back));
  Assert.IsTrue(Back.Kind = erkProgress);
  Assert.AreEqual(Int64(5000000000), Back.Done, 'sizes beyond 32 bits');
  Assert.AreEqual(Int64(9000000000), Back.Total);
  Assert.AreEqual('C:\d\a.bin', Back.Dst);

  Rep := Default(TElevatedReply);
  Rep.Id := 8;
  Rep.Kind := erkDone;
  Rep.Ok := False;
  Rep.Code := vecAccessDenied;
  Rep.Msg := 'Access denied';
  Rep.URI := 'file:///C:/x';
  Assert.IsTrue(DecodeReply(EncodeReply(Rep), Back));
  Assert.IsTrue(Back.Kind = erkDone);
  Assert.IsFalse(Back.Ok);
  Assert.IsTrue(Back.Code = vecAccessDenied);
  Assert.AreEqual('Access denied', Back.Msg);
end;

procedure TTestElevatedProtocol.TestDecodeRejectsGarbage;
var
  Req: TElevatedRequest;
  Rep: TElevatedReply;
begin
  Assert.IsFalse(DecodeRequest(TEncoding.UTF8.GetBytes('not json'), Req));
  Assert.IsFalse(DecodeRequest(TEncoding.UTF8.GetBytes('[1,2]'), Req), 'an array');
  Assert.IsFalse(DecodeRequest(nil, Req), 'empty');
  Assert.IsFalse(DecodeReply(TEncoding.UTF8.GetBytes('{"kind":"x"}'), Rep));
end;

procedure TTestElevatedProtocol.TestDecodeRejectsUnknownOp;
var
  Req: TElevatedRequest;
begin
  Assert.IsFalse(DecodeRequest(TEncoding.UTF8.GetBytes('{"id":1,"op":99}'), Req));
  Assert.IsFalse(DecodeRequest(TEncoding.UTF8.GetBytes('{"id":1,"op":-1}'), Req));
  Assert.IsFalse(DecodeRequest(TEncoding.UTF8.GetBytes('{"id":1}'), Req), 'no op');
  Assert.IsFalse(DecodeRequest(TEncoding.UTF8.GetBytes('{"id":1,"op":1,"mode":9}'), Req),
    'unknown delete mode');
end;

procedure TTestElevatedProtocol.TestFramingAcrossPartialReads;
var
  Framed, Buf, Payload: TBytes;
  I: Integer;
  Invalid: Boolean;
begin
  Framed := FrameBytes(TEncoding.UTF8.GetBytes('hello'));
  Assert.AreEqual(Integer(4 + 5), Integer(Length(Framed)));
  Buf := nil;
  for I := 0 to High(Framed) - 1 do
  begin
    SetLength(Buf, Length(Buf) + 1);
    Buf[High(Buf)] := Framed[I];
    Assert.IsFalse(TryTakeFrame(Buf, Payload, Invalid), 'incomplete after ' + IntToStr(I + 1));
    Assert.IsFalse(Invalid);
  end;
  SetLength(Buf, Length(Buf) + 1);
  Buf[High(Buf)] := Framed[High(Framed)];
  Assert.IsTrue(TryTakeFrame(Buf, Payload, Invalid));
  Assert.AreEqual('hello', TEncoding.UTF8.GetString(Payload));
  Assert.AreEqual(Integer(0), Integer(Length(Buf)), 'buffer is empty after the message');
end;

procedure TTestElevatedProtocol.TestTwoFramesInOneRead;
var
  A, B, Buf, Payload: TBytes;
  Invalid: Boolean;
begin
  A := FrameBytes(TEncoding.UTF8.GetBytes('one'));
  B := FrameBytes(TEncoding.UTF8.GetBytes('two'));
  Buf := A + B;
  Assert.IsTrue(TryTakeFrame(Buf, Payload, Invalid));
  Assert.AreEqual('one', TEncoding.UTF8.GetString(Payload));
  Assert.IsTrue(TryTakeFrame(Buf, Payload, Invalid));
  Assert.AreEqual('two', TEncoding.UTF8.GetString(Payload));
  Assert.IsFalse(TryTakeFrame(Buf, Payload, Invalid));
end;

procedure TTestElevatedProtocol.TestOversizeFrameIsInvalid;
var
  Buf, Payload: TBytes;
  Invalid: Boolean;
begin
  Buf := TBytes.Create($FF, $FF, $FF, $7F, 1, 2, 3);
  Assert.IsFalse(TryTakeFrame(Buf, Payload, Invalid));
  Assert.IsTrue(Invalid, 'a length beyond the limit drops the connection');
end;

procedure TTestElevatedProtocol.TestElevatableUris;
begin
  Assert.IsTrue(IsElevatableUri(PathToFileUri('C:\Program Files\App')), 'drive path');
  Assert.IsTrue(IsElevatableUri(PathToFileUri('C:\')), 'drive root');
  Assert.IsTrue(IsElevatableUri(PathToFileUri('\\server\share\dir')), 'UNC share');
  Assert.IsFalse(IsElevatableUri(''), 'empty');
  Assert.IsFalse(IsElevatableUri('file:///C:/a.zip!/inner.txt'), 'inside an archive');
  Assert.IsFalse(IsElevatableUri('find:///abc'), 'virtual folder');
  Assert.IsFalse(IsElevatableUri('ws:///'), 'workspace folder');
  Assert.IsFalse(IsElevatableUri('C:\Temp\x'), 'a bare path is not a file URI');
  Assert.IsFalse(IsElevatableUri('relative.txt'), 'a bare name');
  Assert.IsTrue(IsElevatableUri('file:///C:/a/../b'), 'parent segment is resolved');
  Assert.AreEqual('C:\b', FileUriToPath('file:///C:/a/../b'));
end;

procedure TTestElevatedProtocol.TestValidateRequest;
var
  Req: TElevatedRequest;
  Reason: string;
begin
  Req := Default(TElevatedRequest);
  Req.Op := eoCopy;
  Req.FromURI := PathToFileUri('C:\a');
  Assert.IsFalse(ValidateRequest(Req, Reason), 'a copy needs a destination');
  Assert.AreNotEqual('', Reason);
  Req.ToURI := PathToFileUri('C:\b');
  Assert.IsTrue(ValidateRequest(Req, Reason));
  Req.ToURI := 'file:///C:/z.zip!/b';
  Assert.IsFalse(ValidateRequest(Req, Reason), 'destination inside an archive');

  Req := Default(TElevatedRequest);
  Req.Op := eoDelete;
  Req.FromURI := 'find:///x';
  Assert.IsFalse(ValidateRequest(Req, Reason));
  Req.FromURI := PathToFileUri('C:\Temp\x');
  Assert.IsTrue(ValidateRequest(Req, Reason));

  Req := Default(TElevatedRequest);
  Req.Op := eoWriteText;
  Req.FromURI := PathToFileUri('C:\Temp\x.txt');
  Req.Text := StringOfChar('x', cElevatedMaxText + 1);
  Assert.IsFalse(ValidateRequest(Req, Reason), 'text over the limit');

  Req := Default(TElevatedRequest);
  Req.Op := eoQuit;
  Assert.IsTrue(ValidateRequest(Req, Reason), 'quit needs no path');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestElevatedProtocol);

end.
