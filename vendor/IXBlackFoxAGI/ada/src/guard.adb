package body Guard with SPARK_Mode => On is
   function Check_Proposal
     (Kind        : Interfaces.C.int;
      Permission  : Interfaces.C.int;
      Risk        : Interfaces.C.int;
      Cost        : Interfaces.C.int;
      Budget      : Interfaces.C.int;
      Samples     : Interfaces.C.int;
      Correct     : Interfaces.C.int;
      Cross_Check : Interfaces.C.int) return Interfaces.C.int is
   begin
      -- Reject all malformed requests before interpreting their intent.
      if Kind not in 0 .. 2
        or else Permission not in 0 .. 1
        or else Risk not in 0 .. 3
        or else Cost not in 0 .. 1_000_000
        or else Budget not in 0 .. 1_000_000
        or else Samples not in 0 .. 1_000_000
        or else Correct < 0 or else Correct > Samples
        or else Cross_Check < 0 or else Cross_Check > Samples
      then
         return 0;
      end if;

      if Kind = 0 then
         return 3; -- Withholding action is always available.
      end if;

      if Permission = 0 or else Cost > Budget then
         return 0;
      end if;

      if Kind = 1 then
         if Risk = 0 then
            return 1;
         else
            return 0;
         end if;
      end if;

      --  Only low-risk, sufficiently corroborated actions pass.
      --  Bounded inputs prevent overflow of 100 * Correct.
      if Risk <= 1
        and then Samples >= 16
        and then Correct * 100 >= Samples * 90
        and then Cross_Check >= 8
      then
         return 2;
      end if;
      return 0;
   end Check_Proposal;
end Guard;
