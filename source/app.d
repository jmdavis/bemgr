// This is to work around the issue that dub replaces app.d when running
// unit tests, so any unittest blocks in app.d are not run.
int main(string[] args)
{
    import realapp;
    return realMain(args);
}
