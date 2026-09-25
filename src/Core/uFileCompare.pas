unit uFileCompare;

{ File content comparison. v1 compared whole buffers and reported equal /
  differs-at-offset. Stage 34 adds a line-based unified diff of two text
  files (Ctrl+Alt+C) so the user sees which lines differ, not only that
  they do. Binary files still fall back to the offset message. }

interface

uses
  System.SysUtils, uVfsTypes;

type
  TCompareResult = (crEqual, crDifferSize, crDifferAtOffset, crReadError);
  TCompareDoneCallback = reference to procedure(AResult: TCompareResult;
    ADiffOffset: Int64; const AError: TVfsError);
  TFileDiffDoneCallback = reference to procedure(AResult: TCompareResult;
    ADiffOffset: Int64; const AError: TVfsError;
    const ADiffLines: TArray<string>; AChangedLines: Integer);

procedure CompareFilesAsync(const AUriLeft, AUriRight: string;
  const AVfs: IVirtualFileSystem; ACancel: IJobCancelToken;
  ADone: TCompareDoneCallback);
procedure DiffFilesAsync(const AUriLeft, AUriRight: string;
  const AVfs: IVirtualFileSystem; ACancel: IJobCancelToken;
  ADone: TFileDiffDoneCallback);
function BuildTextDiff(const ALeftText, ARightText: string;
  out AChangedLines: Integer): TArray<string>;
function FirstByteDiffOffset(const ALeft, ARight: TBytes): Int64;

implementation

uses
  System.Classes, uTextEncoding;

const
  cMaxCompareBytes = 128 * 1024 * 1024;
  cMyersMaxLines = 2500;
  cMaxDiffDisplay = 400;
  cDiffContext = 3;

type
  TDiffKind = (dkEqual, dkDelete, dkInsert);
  TDiffSpan = record
    Kind: TDiffKind;
    Text: string;
  end;

procedure CompareFilesAsync(const AUriLeft, AUriRight: string;
  const AVfs: IVirtualFileSystem; ACancel: IJobCancelToken;
  ADone: TCompareDoneCallback);
begin
  DiffFilesAsync(AUriLeft, AUriRight, AVfs, ACancel,
    procedure(AResult: TCompareResult; ADiffOffset: Int64;
      const AError: TVfsError; const ADiffLines: TArray<string>;
      AChangedLines: Integer)
    begin
      if Assigned(ADone) then
        ADone(AResult, ADiffOffset, AError);
    end);
end;

function FirstByteDiffOffset(const ALeft, ARight: TBytes): Int64;
var
  I, N: Integer;
begin
  if Length(ALeft) <> Length(ARight) then
    Exit(0);
  N := Length(ALeft);
  if N = 0 then
    Exit(-1);
  for I := 0 to N - 1 do
    if ALeft[I] <> ARight[I] then
      Exit(I);
  Result := -1;
end;

procedure SplitLines(const AText: string; out ALines: TArray<string>);
var
  SL: TStringList;
  I: Integer;
begin
  SL := TStringList.Create;
  try
    SL.Text := AText;
    SetLength(ALines, SL.Count);
    for I := 0 to SL.Count - 1 do
      ALines[I] := SL[I];
  finally
    SL.Free;
  end;
end;

procedure AppendSpan(var ASpans: TArray<TDiffSpan>; AKind: TDiffKind;
  const AText: string);
var
  N: Integer;
begin
  N := Length(ASpans);
  SetLength(ASpans, N + 1);
  ASpans[N].Kind := AKind;
  ASpans[N].Text := AText;
end;

function LinearDiff(const ALeft, ARight: TArray<string>): TArray<TDiffSpan>;
var
  I, J, K, Look: Integer;
  Found: Boolean;
begin
  SetLength(Result, 0);
  I := 0;
  J := 0;
  Look := 40;
  while (I <= High(ALeft)) or (J <= High(ARight)) do
  begin
    if (I <= High(ALeft)) and (J <= High(ARight)) and (ALeft[I] = ARight[J]) then
    begin
      AppendSpan(Result, dkEqual, ALeft[I]);
      Inc(I);
      Inc(J);
      Continue;
    end;
    Found := False;
    if I <= High(ALeft) then
    begin
      K := J;
      while (K <= High(ARight)) and (K - J <= Look) do
      begin
        if ARight[K] = ALeft[I] then
        begin
          Found := True;
          Break;
        end;
        Inc(K);
      end;
    end;
    if (I <= High(ALeft)) and not Found then
    begin
      AppendSpan(Result, dkDelete, ALeft[I]);
      Inc(I);
    end
    else if J <= High(ARight) then
    begin
      AppendSpan(Result, dkInsert, ARight[J]);
      Inc(J);
    end
    else if I <= High(ALeft) then
    begin
      AppendSpan(Result, dkDelete, ALeft[I]);
      Inc(I);
    end
    else
      Break;
  end;
end;

function MyersDiff(const ALeft, ARight: TArray<string>): TArray<TDiffSpan>;
var
  N, M, MaxD, D, K, X, Y, Px, Py, Off, Idx, T, EndX: Integer;
  V: TArray<Integer>;
  Trace: TArray<TArray<Integer>>;
  Spans: TArray<TDiffSpan>;
begin
  N := Length(ALeft);
  M := Length(ARight);
  if (N > cMyersMaxLines) or (M > cMyersMaxLines) then
    Exit(LinearDiff(ALeft, ARight));
  MaxD := N + M;
  if MaxD = 0 then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  Off := MaxD;
  SetLength(V, 2 * MaxD + 1);
  SetLength(Trace, 0);
  V[Off + 1] := 0;
  EndX := -1;
  for D := 0 to MaxD do
  begin
    SetLength(Trace, Length(Trace) + 1);
    Trace[High(Trace)] := Copy(V);
    K := -D;
    while K <= D do
    begin
      Idx := Off + K;
      if (K = -D) or ((K <> D) and (V[Idx - 1] < V[Idx + 1])) then
        X := V[Idx + 1]
      else
        X := V[Idx - 1] + 1;
      Y := X - K;
      while (X < N) and (Y < M) and (ALeft[X] = ARight[Y]) do
      begin
        Inc(X);
        Inc(Y);
      end;
      V[Idx] := X;
      if (X >= N) and (Y >= M) then
      begin
          EndX := X;
          Break;
      end;
      Inc(K, 2);
    end;
    if EndX >= 0 then
      Break;
  end;
  if EndX < 0 then
    Exit(LinearDiff(ALeft, ARight));

  SetLength(Spans, 0);
  X := N;
  Y := M;
  for T := High(Trace) downto 0 do
  begin
    D := T;
    V := Trace[T];
    K := X - Y;
    Idx := Off + K;
    if (K = -D) or ((K <> D) and (V[Idx - 1] < V[Idx + 1])) then
    begin
      Px := V[Idx + 1];
      Py := Px - (K + 1);
    end
    else
    begin
      Px := V[Idx - 1];
      Py := Px - (K - 1);
    end;
    while (X > Px) and (Y > Py) do
    begin
      Dec(X);
      Dec(Y);
      AppendSpan(Spans, dkEqual, ALeft[X]);
    end;
    if D = 0 then
      Break;
    if X = Px then
    begin
      Dec(Y);
      AppendSpan(Spans, dkInsert, ARight[Y]);
    end
    else
    begin
      Dec(X);
      AppendSpan(Spans, dkDelete, ALeft[X]);
    end;
    X := Px;
    Y := Py;
  end;

  SetLength(Result, Length(Spans));
  for T := 0 to High(Spans) do
    Result[T] := Spans[High(Spans) - T];
end;

procedure AppendLine(var ALines: TArray<string>; const AText: string);
var
  N: Integer;
begin
  N := Length(ALines);
  SetLength(ALines, N + 1);
  ALines[N] := AText;
end;

function PrefixLine(AKind: TDiffKind; const AText: string): string;
begin
  case AKind of
    dkDelete: Result := '- ' + AText;
    dkInsert: Result := '+ ' + AText;
  else
    Result := '  ' + AText;
  end;
end;

function FormatUnified(const ASpans: TArray<TDiffSpan>;
  out AChangedLines: Integer): TArray<string>;
var
  I, EqualRun, Keep: Integer;
  Show: TArray<Boolean>;
begin
  SetLength(Result, 0);
  AChangedLines := 0;
  SetLength(Show, Length(ASpans));
  I := 0;
  while I <= High(ASpans) do
  begin
    if ASpans[I].Kind <> dkEqual then
    begin
      Show[I] := True;
      if ASpans[I].Kind in [dkDelete, dkInsert] then
        Inc(AChangedLines);
      Inc(I);
      Continue;
    end;
    EqualRun := 0;
    while (I + EqualRun <= High(ASpans)) and
      (ASpans[I + EqualRun].Kind = dkEqual) do
      Inc(EqualRun);
    if EqualRun <= (cDiffContext * 2) then
    begin
      for Keep := 0 to EqualRun - 1 do
        Show[I + Keep] := True;
    end
    else
    begin
      for Keep := 0 to cDiffContext - 1 do
        Show[I + Keep] := True;
      for Keep := EqualRun - cDiffContext to EqualRun - 1 do
        Show[I + Keep] := True;
    end;
    Inc(I, EqualRun);
  end;
  for I := 0 to High(ASpans) do
  begin
    if not Show[I] then
    begin
      if (I = 0) or Show[I - 1] then
        AppendLine(Result, '  ...');
      Continue;
    end;
    AppendLine(Result, PrefixLine(ASpans[I].Kind, ASpans[I].Text));
  end;
  if Length(Result) > cMaxDiffDisplay then
  begin
    I := Length(Result) - cMaxDiffDisplay;
    SetLength(Result, cMaxDiffDisplay + 1);
    Result[cMaxDiffDisplay] := Format('... and %d more lines', [I]);
  end;
end;

function BuildTextDiff(const ALeftText, ARightText: string;
  out AChangedLines: Integer): TArray<string>;
var
  LeftLines, RightLines: TArray<string>;
  Spans: TArray<TDiffSpan>;
begin
  AChangedLines := 0;
  SplitLines(ALeftText, LeftLines);
  SplitLines(ARightText, RightLines);
  if (Length(LeftLines) = 0) and (Length(RightLines) = 0) then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  Spans := MyersDiff(LeftLines, RightLines);
  Result := FormatUnified(Spans, AChangedLines);
end;

procedure DiffFilesAsync(const AUriLeft, AUriRight: string;
  const AVfs: IVirtualFileSystem; ACancel: IJobCancelToken;
  ADone: TFileDiffDoneCallback);
begin
  if not Assigned(AVfs) then
  begin
    if Assigned(ADone) then
      ADone(crReadError, 0, TVfsError.Make(vecIOError, 'No VFS available', AUriLeft),
        nil, 0);
    Exit;
  end;
  AVfs.ReadBytesAsync(AUriLeft, cMaxCompareBytes, ACancel,
    procedure(const ALeftBytes: TBytes; const ALeftErr: TVfsError)
    begin
      if ALeftErr.Code <> vecOk then
      begin
        if Assigned(ADone) then
          ADone(crReadError, 0, ALeftErr, nil, 0);
        Exit;
      end;
      AVfs.ReadBytesAsync(AUriRight, cMaxCompareBytes, ACancel,
        procedure(const ARightBytes: TBytes; const ARightErr: TVfsError)
        var
          Kind: TCompareResult;
          Offset: Int64;
          LeftText, RightText: string;
          LeftEnc, RightEnc: TTextFileEncoding;
          LeftBin, RightBin: Boolean;
          Lines: TArray<string>;
          Changed: Integer;
        begin
          if ARightErr.Code <> vecOk then
          begin
            if Assigned(ADone) then
              ADone(crReadError, 0, ARightErr, nil, 0);
            Exit;
          end;
          if (Length(ALeftBytes) = 0) and (Length(ARightBytes) = 0) then
          begin
            if Assigned(ADone) then
              ADone(crEqual, 0, TVfsError.Ok, nil, 0);
            Exit;
          end;
          if (Length(ALeftBytes) = Length(ARightBytes)) and
             ((Length(ALeftBytes) = 0) or
              CompareMem(@ALeftBytes[0], @ARightBytes[0], Length(ALeftBytes))) then
          begin
            if Assigned(ADone) then
              ADone(crEqual, 0, TVfsError.Ok, nil, 0);
            Exit;
          end;
          if Length(ALeftBytes) <> Length(ARightBytes) then
            Kind := crDifferSize
          else
            Kind := crDifferAtOffset;
          Offset := FirstByteDiffOffset(ALeftBytes, ARightBytes);
          DetectAndDecodeText(ALeftBytes, LeftText, LeftEnc, LeftBin);
          DetectAndDecodeText(ARightBytes, RightText, RightEnc, RightBin);
          if LeftBin or RightBin then
          begin
            if Assigned(ADone) then
              ADone(Kind, Offset, TVfsError.Ok, nil, 0);
            Exit;
          end;
          Lines := BuildTextDiff(LeftText, RightText, Changed);
          if Assigned(ADone) then
            ADone(Kind, Offset, TVfsError.Ok, Lines, Changed);
        end);
    end);
end;

end.
