with Interfaces.C;
package Guard with SPARK_Mode => On is
   use type Interfaces.C.int;
   --  Result: 0 deny, 1 permit EXPLORE, 2 permit ACT, 3 HOLD.
   --  The entire decision is pure. It grants no operating-system permissions.
   function Check_Proposal
     (Kind        : Interfaces.C.int;
      Permission  : Interfaces.C.int;
      Risk        : Interfaces.C.int;
      Cost        : Interfaces.C.int;
      Budget      : Interfaces.C.int;
      Samples     : Interfaces.C.int;
      Correct     : Interfaces.C.int;
      Cross_Check : Interfaces.C.int) return Interfaces.C.int
   with Global => null,
        Post => Check_Proposal'Result in 0 .. 3
          and then
          (if Check_Proposal'Result = 2 then
             Kind = 2 and Permission = 1 and Risk <= 1
             and Cost <= Budget and Samples >= 16
             and Cross_Check >= 8)
          and then
          (if Check_Proposal'Result = 1 then
             Kind = 1 and Permission = 1 and Risk = 0
             and Cost <= Budget);
   pragma Export (C, Check_Proposal, "ixbf_check_proposal");
end Guard;
