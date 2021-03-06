//
//  iTermPythonArgumentParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/11/18.
//

#import "iTermPythonArgumentParser.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermPythonArgumentParser

- (instancetype)initWithArgs:(NSArray<NSString *> *)args {
    self = [super init];
    if (self) {
        _fullPythonPath = [args[0] copy];
        if (args.count == 0) {
            _args = @[];
        } else {
            _args = [[args subarrayFromIndex:1] copy];
        }
        [self parse];
    }
    return self;
}

- (BOOL)argsLookLikeRepl:(NSArray<NSString *> *)args {
    if ([args[0] isEqualToString:@"aioconsole"]) {
        if (args.count == 1) {
            return YES;
        } else if (args.count == 3 &&
                   [args[1] isEqualToString:@"--no-readline"] &&
                   [args[2] hasPrefix:@"--banner="]) {
            return YES;
        } else if (args.count == 4 &&
                   [args[1] isEqualToString:@"--no-readline"] &&
                   [args[2] isEqualToString:@"--prompt-control"] &&
                   [args[3] hasPrefix:@"--banner="]) {
            return YES;
        }
    }
    return NO;
}

- (void)parse {
    enum {
        iTermPythonArgumentParserFoundNone,
        iTermPythonArgumentParserFoundModule,
        iTermPythonArgumentParserFoundStatement,
        iTermPythonArgumentParserFoundArgument
    } found = iTermPythonArgumentParserFoundNone;

    NSInteger i = -1;
    for (NSString *arg in _args) {
        i++;
        BOOL ignore = NO;
        switch (found) {
            case iTermPythonArgumentParserFoundNone:
                // Previous argument does not affect how this one is parsed
                break;

            case iTermPythonArgumentParserFoundModule: {
                [self handleModule:[_args subarrayFromIndex:i]];
                return;
            }

            case iTermPythonArgumentParserFoundStatement:
                // arg follows -c
                [self handleStatement:arg];
                return;

            case iTermPythonArgumentParserFoundArgument:
                // arg follows -Q or -W, of which this is the parameter
                ignore = YES;
                break;
        }
        if (ignore) {
            found = iTermPythonArgumentParserFoundNone;
            continue;
        }

        if ([arg isEqualToString:@"-m"]) {
            found = iTermPythonArgumentParserFoundModule;
        } else if ([arg hasPrefix:@"-m"]) {
            NSArray *moduleArgs = [ @[ [arg substringFromIndex:2] ] arrayByAddingObjectsFromArray:[_args subarrayFromIndex:i + 1]];
            [self handleModule:moduleArgs];
            return;
        } else if ([arg isEqualToString:@"-Q"] ||
                   [arg isEqualToString:@"-W"]) {
            found = iTermPythonArgumentParserFoundArgument;
        } else if ([arg isEqualToString:@"-c"]) {
            found = iTermPythonArgumentParserFoundStatement;
        } else if ([arg hasPrefix:@"-c"]) {
            [self handleStatement:[arg substringFromIndex:2]];
            return;
        } else if ([arg isEqualToString:@"-"]) {
            return;
        } else if ([arg hasPrefix:@"-"]) {
            found = iTermPythonArgumentParserFoundNone;
        } else {
            _script = arg;
            return;
        }
    }
}

- (void)handleModule:(NSArray *)args {
    // If a module is specified that changes how Python parses its command line so we
    // cannot go on.
    if ([self argsLookLikeRepl:args]) {
        // Except for when it's aioconsole with known arguments. That's just the REPL.
        _repl = YES;
        return;
    }
    // Just glom everything after -m into the module argument because we can't
    // parse it.
    NSArray<NSString *> *moduleArgs = args;
    _module = [moduleArgs componentsJoinedByString:@" "];
    _escapedModule = [[moduleArgs mapWithBlock:^id(NSString *anObject) {
        return [anObject stringWithBackslashEscapedShellCharactersIncludingNewlines:YES];
    }] componentsJoinedByString:@" "];
}

- (void)handleStatement:(NSString *)arg {
    _statement = arg;
}

- (NSString *)escapedScript {
    return [_script stringWithBackslashEscapedShellCharactersIncludingNewlines:YES];
}

- (NSString *)escapedStatement {
    return [_statement stringWithBackslashEscapedShellCharactersIncludingNewlines:YES];
}

- (NSString *)escapedFullPythonPath {
    return [_fullPythonPath stringWithBackslashEscapedShellCharactersIncludingNewlines:YES];
}

@end

NS_ASSUME_NONNULL_END
