import java.io.* ;
import java.util.Scanner ;

public class test {

    /**
     * @param args the command line arguments
     */
    public static void main(String[] args) throws IOException
    {
        StdAudio myAudio = new StdAudio() ;
	Scanner scan = new Scanner(System.in) ;

	System.out.println("Input the name of the wave file.") ;

	String waveInput = scan.next() ;

	System.out.println("Input the name of the output file.") ;

	String outputFile = scan.next() ;

        File file = new File(outputFile) ;

        file.createNewFile() ;

        FileWriter writer = new FileWriter(file) ;

        double d[] = myAudio.read(waveInput) ;

        for(int i = 0 ; i < d.length ; i++)
        {
            writer.write(d[i] + "\n") ;
        }

        writer.flush();
        writer.close();
    }
}

