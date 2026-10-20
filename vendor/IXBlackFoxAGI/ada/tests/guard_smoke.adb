with Interfaces.C;
with Ada.Text_IO;
with Guard;
procedure Guard_Smoke is
   use type Interfaces.C.int;
   -- Need to make Interfaces.C visible for use-type and literal comparisons.
   function Check (K, P, R, C, B, N, OK, X : Interfaces.C.int)
                   return Interfaces.C.int renames Guard.Check_Proposal;
   procedure Expect (Actual, Expected : Interfaces.C.int) is
   begin
      if Actual /= Expected then
         raise Program_Error with "guard regression";
      end if;
   end Expect;
begin
   Expect (Check (2, 1, 0, 1, 5, 20, 19, 10), 2);
   Expect (Check (2, 1, 0, 1, 5, 20, 10, 10), 0);
   Expect (Check (2, 0, 0, 1, 5, 20, 20, 10), 0);
   Expect (Check (2, 1, 2, 1, 5, 20, 20, 10), 0);
   Expect (Check (1, 1, 0, 1, 5, 0, 0, 0), 1);
   Expect (Check (1, 1, 1, 1, 5, 0, 0, 0), 0);
   Expect (Check (2, 1, 0, 9, 5, 20, 20, 10), 0);
   Expect (Check (0, 0, 3, 0, 0, 0, 0, 0), 3);
   Expect (Check (2, 1, 0, 0, 5, 0, 0, 0), 0);
   Expect (Check (2, 1, 0, 0, 5, 1_000_001, 1, 1), 0);
   Ada.Text_IO.Put_Line ("Ada guard smoke: passed");
end Guard_Smoke;
