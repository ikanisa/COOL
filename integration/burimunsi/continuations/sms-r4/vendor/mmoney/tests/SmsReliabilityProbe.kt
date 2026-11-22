import com.ikanisa.mmoney.platform.SmsReliabilityContractCases

fun main() {
    val names = SmsReliabilityContractCases.run()
    check(names.size == 45 && names.toSet().size == names.size)
    println("{\"status\":\"passed\",\"checks\":" + names.size + ",\"names\":[" + names.joinToString(",") { "\"$it\"" } + "]}")
}
