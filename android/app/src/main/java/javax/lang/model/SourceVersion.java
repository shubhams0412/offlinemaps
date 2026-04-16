package javax.lang.model;

import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

public enum SourceVersion {
    RELEASE_0, RELEASE_1, RELEASE_2, RELEASE_3, RELEASE_4, RELEASE_5, RELEASE_6, RELEASE_7, RELEASE_8;

    private static final Set<String> keywords;

    static {
        Set<String> s = new HashSet<>();
        String[] kds = {
                "abstract", "continue", "for", "new", "switch", "assert", "default", "if", "package", "synchronized",
                "boolean", "do", "goto", "private", "this", "break", "double", "implements", "protected", "throw",
                "byte", "else", "import", "public", "throws", "case", "enum", "instanceof", "return", "transient",
                "catch", "extends", "int", "short", "try", "char", "final", "interface", "static", "void",
                "class", "finally", "long", "strictfp", "volatile", "const", "float", "native", "super", "while",
                "true", "false", "null"
        };
        Collections.addAll(s, kds);
        keywords = Collections.unmodifiableSet(s);
    }

    public static boolean isIdentifier(CharSequence name) {
        String id = name.toString();
        if (id.isEmpty())
            return false;
        if (!Character.isJavaIdentifierStart(id.charAt(0)))
            return false;
        for (int i = 1; i < id.length(); i++) {
            if (!Character.isJavaIdentifierPart(id.charAt(i)))
                return false;
        }
        return !isKeyword(id);
    }

    // 🔥 Ye function missing tha jis wajah se crash hua
    public static boolean isKeyword(CharSequence s) {
        return keywords.contains(s.toString());
    }
}