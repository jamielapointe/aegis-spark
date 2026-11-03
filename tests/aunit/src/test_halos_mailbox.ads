with AUnit.Test_Cases;

package Test_Halos_Mailbox is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Test_Case);
   overriding function Name (T : Test_Case) return AUnit.Message_String;

   procedure Test_Empty_Channel_Pop (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Corrupt_Magic_Rejection (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_CRC32_Calculation (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Valid_Push_And_Pop (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Sequence_Gap_Detection (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Stale_Timestamp_Rejection (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Halos_Mailbox;
