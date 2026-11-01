unit uPluginPanelServices;

{ What plugins may ask of the documents and panels on screen, answered by the
  dual panel window. Both hosts (the FMX window and the terminal program) hand
  the window and a repaint callback to BuildPanelPluginServices and register the
  result with SetPluginHostServices. }

interface

uses
  System.SysUtils, uPluginServices, uDualPanelWindow;

/// <summary>AWindow returns the panel window (nil while there is none), AIsActive
/// whether it is the window on top, ARecompose repaints after a change.</summary>
function BuildPanelPluginServices(const AWindow: TFunc<TDualPanelWindow>;
  const AIsActive: TFunc<Boolean>; const ARecompose: TProc): TPluginHostServices;

implementation

function BuildPanelPluginServices(const AWindow: TFunc<TDualPanelWindow>;
  const AIsActive: TFunc<Boolean>; const ARecompose: TProc): TPluginHostServices;
begin
  Result := Default(TPluginHostServices);
  Result.DocInfo :=
    function: string
    begin
      if Assigned(AWindow()) and AIsActive() then
        Result := AWindow().PluginDocInfoJson
      else
        Result := '';
    end;
  Result.DocGetText :=
    function(AWhat: Integer; out AText: string): Boolean
    begin
      AText := '';
      Result := Assigned(AWindow()) and AWindow().PluginDocGetText(AWhat, AText);
    end;
  Result.DocReplace :=
    function(AWhat: Integer; const AText: string): Boolean
    begin
      Result := Assigned(AWindow()) and AWindow().PluginDocReplace(AWhat, AText);
      if Result then
        ARecompose();
    end;
  Result.DocSetCursor :=
    function(ARow, ACol: Integer): Boolean
    begin
      Result := Assigned(AWindow()) and AWindow().PluginDocSetCursor(ARow, ACol);
      if Result then
        ARecompose();
    end;
  Result.PanelInfo :=
    function: string
    begin
      if Assigned(AWindow()) then
        Result := AWindow().PluginPanelInfoJson
      else
        Result := '';
    end;
  Result.PanelGoto :=
    function(ASide: Integer; const AURI: string): Boolean
    begin
      Result := Assigned(AWindow()) and AWindow().PluginPanelGoto(ASide, AURI);
      if Result then
        ARecompose();
    end;
  Result.OpenDocument :=
    function(const AURI: string; AEdit: Boolean): Boolean
    begin
      Result := Assigned(AWindow()) and AWindow().PluginOpenDocument(AURI, AEdit);
      if Result then
        ARecompose();
    end;
  Result.PanelRefresh :=
    procedure
    begin
      if Assigned(AWindow()) then
      begin
        AWindow().PluginPanelRefresh;
        ARecompose();
      end;
    end;
  Result.PanelList :=
    function(ASide: Integer): string
    begin
      if Assigned(AWindow()) then
        Result := AWindow().PluginPanelListJson(ASide)
      else
        Result := '';
    end;
  Result.PanelSetCursor :=
    function(ASide: Integer; const AURI: string): Boolean
    begin
      Result := Assigned(AWindow()) and AWindow().PluginPanelSetCursor(ASide, AURI);
      if Result then
        ARecompose();
    end;
  Result.PanelSelect :=
    function(ASide, AMode: Integer; const AArg: string): Boolean
    begin
      Result := Assigned(AWindow()) and AWindow().PluginPanelSelect(ASide, AMode, AArg);
      if Result then
        ARecompose();
    end;
  Result.DocSetSelection :=
    function(ARow1, ACol1, ARow2, ACol2: Integer): Boolean
    begin
      Result := Assigned(AWindow()) and AWindow().PluginDocSetSelection(ARow1, ACol1, ARow2, ACol2);
      if Result then
        ARecompose();
    end;
  Result.DocLine :=
    function(AIndex: Integer; out AText: string): Boolean
    begin
      AText := '';
      Result := Assigned(AWindow()) and AWindow().PluginDocLine(AIndex, AText);
    end;
end;

end.
