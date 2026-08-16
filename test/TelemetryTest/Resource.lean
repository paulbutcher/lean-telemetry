/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Sdk.Resource
import TelemetryTest.Harness

namespace TelemetryTest.Resource

open Telemetry Telemetry.Sdk Telemetry.Sdk.Resource

private def detected : Attrs :=
  [(Conventions.hostName, .str "box"), (Conventions.serviceName, .str "detected")]

private theorem lookup_isSome [BEq α] [LawfulBEq α] (l : List (α × β)) (k : α) :
    (l.lookup k).isSome = l.any (fun p => p.1 == k) := by
  induction l with
  | nil => simp
  | cons p t ih =>
    rcases p with ⟨key, v⟩
    by_cases h : k = key
    · simp_all
    · simp [List.lookup_cons, beq_eq_false_iff_ne.mpr h,
        beq_eq_false_iff_ne.mpr (fun e => h (Eq.symm e)), ih]

/--
Precedence is the whole purpose of `merge`, and the examples below can only reach the pairs
of attribute lists someone thought to write down.
-/
theorem merge_lookup (lower upper : Attrs) (k : String) :
    (merge lower upper).lookup k = (upper.lookup k).or (lower.lookup k) := by
  induction lower with
  | nil => simp [merge]
  | cons p t ih =>
    rcases p with ⟨key, v⟩
    simp only [merge, List.filter_cons] at ih ⊢
    by_cases h : k = key
    · subst h
      by_cases hk : upper.any (fun q => q.1 == k)
      · have hsome : (upper.lookup k).isSome := by rw [lookup_isSome]; exact hk
        cases hu : upper.lookup k with
        | none => rw [hu] at hsome; simp at hsome
        | some w => simp [hk, hu, ih]
      · have hnone : upper.lookup k = none := by
          have h' := lookup_isSome upper k
          simp only [Bool.not_eq_true] at hk
          rw [hk] at h'
          exact Option.not_isSome_iff_eq_none.mp (by simp [h'])
        simp [hk, hnone]
    · have hne : (k == key) = false := beq_eq_false_iff_ne.mpr h
      by_cases hk : upper.any (fun q => q.1 == key)
      · simp [hk, List.lookup_cons, hne, ih]
      · simp [hk, List.lookup_cons, hne, ih]

/-- Precedence decides which value survives, never whether an attribute survives at all. -/
theorem merge_lookup_isSome (lower upper : Attrs) (k : String) :
    ((merge lower upper).lookup k).isSome
      = ((lower.lookup k).isSome || (upper.lookup k).isSome) := by
  rw [merge_lookup]
  cases upper.lookup k <;> cases lower.lookup k <;> rfl

def suite : TestM Unit := do
  checkEq "pairs are split on the first equals sign"
    (parseAttributes "deployment.environment=staging,url=https://x/?a=b")
    [("deployment.environment", .str "staging"), ("url", .str "https://x/?a=b")]
  checkEq "surrounding space is not part of the key or value"
    (parseAttributes " a = 1 ") [("a", .str "1")]
  checkEq "pairs that are not pairs are dropped"
    (parseAttributes "novalue,=nokey,a=1") [("a", .str "1")]

  checkEq "the more explicit source wins"
    (merge [("a", .str "low"), ("b", .str "low")] [("a", .str "high")])
    [("b", .str "low"), ("a", .str "high")]

  let assembled := assemble detected (some "service.name=fromAttributes,extra=1") none
  checkEq "OTEL_RESOURCE_ATTRIBUTES beats what was detected"
    (assembled.attrs.lookup Conventions.serviceName) (some (.str "fromAttributes"))
  let named := assemble detected (some "service.name=fromAttributes") (some "fromServiceName")
  checkEq "OTEL_SERVICE_NAME beats OTEL_RESOURCE_ATTRIBUTES"
    (named.attrs.lookup Conventions.serviceName) (some (.str "fromServiceName"))
  checkEq "detected attributes survive alongside" (named.attrs.lookup Conventions.hostName)
    (some (.str "box"))

  let host := (← Telemetry.Sdk.Resource.detect).attrs.lookup Conventions.hostName
  check "a host name is always reported" host.isSome

end TelemetryTest.Resource
