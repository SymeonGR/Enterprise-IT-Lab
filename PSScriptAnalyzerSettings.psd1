@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Interactive lab scripts: progress messages are meant for the console
        'PSAvoidUsingWriteHost'
    )
}
