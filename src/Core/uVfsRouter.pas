unit uVfsRouter;

{ Compatibility shim: prefer uVfsRegistry.CreateDefaultVfs.
  Old TVfsRouter.Create(File,Zip,Find) call sites should migrate. }

interface

uses
  uVfsTypes, uVfsRegistry;

type
  TVfsRouter = class
  public
    class function CreateDefault: IVirtualFileSystem; static;
  end;

implementation

class function TVfsRouter.CreateDefault: IVirtualFileSystem;
begin
  Result := CreateDefaultVfs;
end;

end.
