-- Static compatibility sentinel only. Do not copy this file into UE4SS_Signatures.
-- UE4SS 1109's integrated PatternSleuth scanner resolves and verifies FName on
-- Far Far West UE 5.8. Supplying the old custom override makes runtime
-- verification fail repeatedly even though this byte sequence is unique.
function Register()
    return "48 89 5C 24 ?? 57 48 83 EC 30 48 8B D9 48 89 54 24 20 33 C9 41 8B F8 4C 8B D2 44 8B C9 48 85 D2"
end
