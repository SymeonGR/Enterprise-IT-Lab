@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Interactive lab scripts write status for the operator
        'PSAvoidUsingWriteHost'
    )
}
