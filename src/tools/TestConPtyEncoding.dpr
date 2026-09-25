program TestConPtyEncoding;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes,
  uConPty in '..\Core\uConPty.pas',
  uShellProfiles in '..\Core\uShellProfiles.pas';

procedure ExpectEq(const AActual, AExpected, AMsg: string);
begin
  if AActual <> AExpected then
    raise Exception.CreateFmt('FAIL %s: expected "%s", got "%s"',
      [AMsg, AExpected, AActual]);
end;

procedure TestUtf8SplitAcrossChunks;
var
  Pty: TConPtySession;
  Utf8Hello: TBytes;
  Part1, Part2: TBytes;
  S, Expected: string;
begin
  Writeln('TestUtf8SplitAcrossChunks');
  Expected := WideChar($041F) + WideChar($0440) + WideChar($0438) + WideChar($0432) +
    WideChar($0435) + WideChar($0442);
  Pty := TConPtySession.Create;
  try
    Pty.ProfileId := cShellProfilePowerShell;
    Utf8Hello := TEncoding.UTF8.GetBytes(Expected);
    // Split inside the two-byte Cyrillic lead (0xD0).
    SetLength(Part1, 1);
    Part1[0] := Utf8Hello[0];
    SetLength(Part2, Length(Utf8Hello) - 1);
    Move(Utf8Hello[1], Part2[0], Length(Part2));

    S := Pty.DecodeOutputChunk(Part1);
    ExpectEq(S, '', 'incomplete lead byte yields empty string');
    S := Pty.DecodeOutputChunk(Part2);
    ExpectEq(S, Expected, 'remainder completes multibyte tail');
  finally
    Pty.Free;
  end;
end;

// Real ConPTY normalizes every profile's console output to UTF-8 before it
// reaches TConPtySession -- cmd.exe's OEM866 console buffer writes get
// translated by conhost exactly like PowerShell/WSL's native UTF-8. This
// replaces the old TestOemCmdChunk, which locked in the pre-Stage-22 pipe
// backend's behavior (cmd emitted raw OEM866); under real ConPTY, decoding
// cmd's actual bytes as CP866 produces mojibake -- confirmed by manual
// testing of the Stage 22 alt-screen work.
procedure TestCmdProfileDecodesUtf8;
var
  Pty: TConPtySession;
  Utf8: TBytes;
  Expected: string;
begin
  Writeln('TestCmdProfileDecodesUtf8');
  Pty := TConPtySession.Create;
  try
    Pty.ProfileId := cShellProfileCmd;
    Expected := WideChar($0442) + WideChar($0435) + WideChar($0441) + WideChar($0442); // "тест"
    Utf8 := TEncoding.UTF8.GetBytes(Expected);
    ExpectEq(Pty.DecodeOutputChunk(Utf8), Expected, 'cmd profile decodes UTF-8 under real ConPTY');
  finally
    Pty.Free;
  end;
end;

begin
  try
    TestUtf8SplitAcrossChunks;
    TestCmdProfileDecodesUtf8;
    Writeln('TestConPtyEncoding passed.');
  except
    on E: Exception do
    begin
      Writeln(E.Message);
      Halt(1);
    end;
  end;
end.
